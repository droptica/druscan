<?php
// User roles and permissions analysis - all data collected in ONE Drupal bootstrap.
// Run by: scripts/analyze_user_roles.sh (through drush_php).
// Output: JSON with user_statistics, roles, security_analysis, summary

$db = \Drupal::database();
$entity_type_manager = \Drupal::entityTypeManager();
$user_storage = $entity_type_manager->getStorage('user');
$roles = $entity_type_manager->getStorage('user_role')->loadMultiple();

$count = function ($where) use ($db) {
  return (int) $db->query("SELECT COUNT(*) FROM {users_field_data} WHERE uid > 0" . ($where ? " AND $where" : ''))->fetchField();
};

$user_summary = function ($user) {
  $last_login = $user->getLastLoginTime();
  return [
    'uid' => $user->id(),
    'name' => $user->getAccountName(),
    'email' => $user->getEmail(),
    'status' => $user->isActive() ? 'active' : 'blocked',
    'last_login' => $last_login ? date('Y-m-d H:i:s', $last_login) : NULL,
  ];
};

// ---------------------------------------------------------------------------
// User statistics
// ---------------------------------------------------------------------------

$registrations = [];
$query = $db->query("
  SELECT DATE_FORMAT(FROM_UNIXTIME(created), '%Y-%m') AS month, COUNT(*) AS count
  FROM {users_field_data}
  WHERE uid > 0 AND created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 12 MONTH))
  GROUP BY DATE_FORMAT(FROM_UNIXTIME(created), '%Y-%m')
  ORDER BY month DESC
  LIMIT 12
");
foreach ($query as $row) {
  $registrations[] = ['month' => $row->month, 'count' => (int) $row->count];
}

$user_statistics = [
  'total_users' => $count(''),
  'active_users' => $count('status = 1'),
  'blocked_users' => $count('status = 0'),
  'active_last_30_days' => $count('login > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))'),
  'registrations_last_12_months' => $registrations,
];

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------

$roles_data = [];
foreach ($roles as $role_id => $role) {
  $role_data = [
    'role_id' => $role_id,
    'label' => $role->label(),
    'weight' => $role->getWeight(),
    'is_admin' => $role->isAdmin(),
    'permissions_count' => 0,
    'user_count' => 0,
    'users' => [],
    'permissions' => [],
  ];

  $permissions = $role->getPermissions();
  $role_data['permissions_count'] = count($permissions);

  // Group permissions by category
  $grouped_perms = [
    'administration' => [],
    'content_management' => [],
    'access_view' => [],
    'usage' => [],
    'other' => [],
  ];
  foreach ($permissions as $permission) {
    if (strpos($permission, 'administer') === 0) {
      $grouped_perms['administration'][] = $permission;
    }
    elseif (strpos($permission, 'create') === 0 || strpos($permission, 'edit') === 0 || strpos($permission, 'delete') === 0) {
      $grouped_perms['content_management'][] = $permission;
    }
    elseif (strpos($permission, 'view') === 0 || strpos($permission, 'access') === 0) {
      $grouped_perms['access_view'][] = $permission;
    }
    elseif (strpos($permission, 'use') === 0) {
      $grouped_perms['usage'][] = $permission;
    }
    else {
      $grouped_perms['other'][] = $permission;
    }
  }
  $role_data['permissions'] = $grouped_perms;

  // Users for custom roles (exclude anonymous, authenticated)
  if (!in_array($role_id, ['anonymous', 'authenticated'])) {
    $users = $user_storage->loadByProperties(['roles' => $role_id]);
    $role_data['user_count'] = count($users);

    // Only include user details if count is reasonable (<=20)
    if (count($users) > 0 && count($users) <= 20) {
      foreach ($users as $user) {
        $role_data['users'][] = $user_summary($user);
      }
    }
  }
  elseif ($role_id === 'authenticated') {
    // For authenticated role, count all users
    $role_data['user_count'] = (int) \Drupal::entityQuery('user')
      ->accessCheck(FALSE)
      ->condition('uid', 0, '>')
      ->count()
      ->execute();
  }

  $roles_data[] = $role_data;
}

// ---------------------------------------------------------------------------
// Security analysis
// ---------------------------------------------------------------------------

$admin_users = [];
foreach ($user_storage->loadByProperties(['roles' => 'administrator']) as $user) {
  $admin_users[] = $user_summary($user);
}

$multi_role_users = [];
$query = $db->query("
  SELECT u.uid, u.name, u.mail, GROUP_CONCAT(ur.roles_target_id) AS roles, COUNT(ur.roles_target_id) AS role_count
  FROM {users_field_data} u
  JOIN {user__roles} ur ON u.uid = ur.entity_id
  WHERE u.uid > 0
  GROUP BY u.uid, u.name, u.mail
  HAVING COUNT(ur.roles_target_id) > 1
  ORDER BY role_count DESC
  LIMIT 50
");
foreach ($query as $row) {
  $multi_role_users[] = [
    'uid' => (int) $row->uid,
    'name' => $row->name,
    'email' => $row->mail,
    'roles' => explode(',', $row->roles),
    'role_count' => (int) $row->role_count,
  ];
}

$blocked_with_roles = [];
$query = $db->query("
  SELECT u.uid, u.name, u.mail, GROUP_CONCAT(ur.roles_target_id) AS roles
  FROM {users_field_data} u
  LEFT JOIN {user__roles} ur ON u.uid = ur.entity_id
  WHERE u.uid > 0 AND u.status = 0
  GROUP BY u.uid, u.name, u.mail
  LIMIT 50
");
foreach ($query as $row) {
  $blocked_with_roles[] = [
    'uid' => (int) $row->uid,
    'name' => $row->name,
    'email' => $row->mail,
    'roles' => $row->roles ? explode(',', $row->roles) : [],
  ];
}

$security_analysis = [
  'admin_users' => $admin_users,
  'admin_users_count' => count($admin_users),
  'multi_role_users' => $multi_role_users,
  'multi_role_users_count' => count($multi_role_users),
  'blocked_users_with_roles' => $blocked_with_roles,
  'blocked_users_count' => count($blocked_with_roles),
];

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

$system_roles = ['anonymous', 'authenticated', 'administrator'];
$custom_roles = 0;
foreach (array_keys($roles) as $role_id) {
  if (!in_array($role_id, $system_roles)) {
    $custom_roles++;
  }
}

echo json_encode([
  'user_statistics' => $user_statistics,
  'roles' => $roles_data,
  'security_analysis' => $security_analysis,
  'summary' => [
    'total_roles' => count($roles),
    'custom_roles' => $custom_roles,
    'system_roles' => count($roles) - $custom_roles,
  ],
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR);
