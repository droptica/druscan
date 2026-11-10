<?php
// Drupal Canvas analysis - all data collected in ONE Drupal bootstrap.
// Run by: scripts/analyze_canvas.sh (through drush_php).
//
// Drupal Canvas (drupal/canvas, earlier "Experience Builder") is a visual page builder:
// editors build pages from components. Components come from several sources:
//   sdc    - Single Directory Components written in code (theme or module)
//   js     - "code components" written in the browser, stored in configuration
//   block  - Drupal blocks made available as components
//   others - e.g. theme page template, markers
//
// Output: JSON with module, summary, homepage, pages, components, content_templates,
//         page_regions, patterns

$module_handler = \Drupal::moduleHandler();
$entity_type_manager = \Drupal::entityTypeManager();
$module_list = \Drupal::service('extension.list.module');
$theme_list = \Drupal::service('extension.list.theme');

$PAGES_LIMIT = 100;
$USAGE_LIMIT = 15;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Version of a module: info file first, then Composer.
$module_version = function ($name) use ($module_list) {
  $version = NULL;
  try {
    $version = $module_list->getExtensionInfo($name)['version'] ?? NULL;
  }
  catch (\Throwable $e) {
  }
  if (!$version && class_exists('\Composer\InstalledVersions')) {
    try {
      if (\Composer\InstalledVersions::isInstalled('drupal/' . $name)) {
        $version = \Composer\InstalledVersions::getPrettyVersion('drupal/' . $name);
      }
    }
    catch (\Throwable $e) {
    }
  }
  return $version ?: NULL;
};

// Where an extension (module or theme) lives: custom, contrib, core or unknown.
$extension_origin = function ($name) use ($module_list, $theme_list) {
  if ($name === NULL || $name === '') {
    return ['type' => 'unknown', 'kind' => NULL];
  }
  if ($name === 'core') {
    return ['type' => 'core', 'kind' => 'core'];
  }
  foreach (['module' => $module_list, 'theme' => $theme_list] as $kind => $list) {
    try {
      if ($list->exists($name)) {
        $path = $list->getPath($name);
        if (strpos($path, 'core/') === 0) {
          $type = 'core';
        }
        elseif (strpos($path, '/custom/') !== FALSE) {
          $type = 'custom';
        }
        elseif (strpos($path, '/contrib/') !== FALSE) {
          $type = 'contrib';
        }
        else {
          // e.g. themes/my_theme or profiles/... - not downloaded to a contrib folder
          $type = 'custom';
        }
        return ['type' => $type, 'kind' => $kind];
      }
    }
    catch (\Throwable $e) {
    }
  }
  return ['type' => 'unknown', 'kind' => NULL];
};

// Load all config entities of a type (empty list when the type does not exist).
$load_all = function ($entity_type_id) use ($entity_type_manager) {
  try {
    if (!$entity_type_manager->hasDefinition($entity_type_id)) {
      return [];
    }
    return $entity_type_manager->getStorage($entity_type_id)->loadMultiple();
  }
  catch (\Throwable $e) {
    return [];
  }
};

// Component usage counter: component id => number of places it is used.
$usage = [];
$count_tree = function ($tree) use (&$usage) {
  $count = 0;
  if (!is_array($tree)) {
    return $count;
  }
  foreach ($tree as $item) {
    if (is_array($item) && !empty($item['component_id'])) {
      $usage[$item['component_id']] = ($usage[$item['component_id']] ?? 0) + 1;
      $count++;
    }
  }
  return $count;
};

$source_labels = [
  'sdc' => ['label' => 'Code-defined components (SDC)', 'description' => 'Single Directory Components written in a theme or module (in the codebase)'],
  'js' => ['label' => 'Code components (created in Canvas)', 'description' => 'Components written in the Canvas in-browser code editor, stored in configuration'],
  'block' => ['label' => 'Blocks', 'description' => 'Drupal blocks made available as Canvas components'],
  'theme_page_template' => ['label' => 'Theme page template', 'description' => 'Page template of the theme used as a component'],
  'marker' => ['label' => 'Markers', 'description' => 'Technical placeholders (e.g. main page content)'],
];

// ---------------------------------------------------------------------------
// 1. Module status
// ---------------------------------------------------------------------------

$in_codebase = FALSE;
try {
  $in_codebase = $module_list->exists('canvas');
}
catch (\Throwable $e) {
}
$enabled = $module_handler->moduleExists('canvas');

$related_modules = [];
try {
  foreach ($module_list->getList() as $name => $extension) {
    if ($name !== 'canvas' && strpos($name, 'canvas') === 0) {
      $is_submodule = strpos($extension->getPath(), '/canvas/modules/') !== FALSE;
      $is_enabled = $module_handler->moduleExists($name);
      // Skip disabled sub-modules shipped inside Canvas (many dev/test helpers).
      if ($is_submodule && !$is_enabled) {
        continue;
      }
      $related_modules[] = [
        'name' => $name,
        'label' => $extension->info['name'] ?? $name,
        'enabled' => $is_enabled,
        'version' => $module_version($name),
        'type' => $is_submodule ? 'canvas_submodule' : 'separate_module',
      ];
    }
  }
}
catch (\Throwable $e) {
}

$output = [
  'module' => [
    'in_codebase' => $in_codebase,
    'enabled' => $enabled,
    'version' => $in_codebase ? $module_version('canvas') : NULL,
    'related_modules' => $related_modules,
  ],
  'summary' => [
    'pages_total' => 0,
    'pages_published' => 0,
    'pages_unpublished' => 0,
    'components_total' => 0,
    'components_enabled' => 0,
    'custom_code_components' => 0,
    'in_browser_code_components' => 0,
    'content_templates' => 0,
    'page_regions' => 0,
    'patterns' => 0,
    'folders' => 0,
  ],
  'homepage' => ['front_page' => \Drupal::config('system.site')->get('page.front'), 'is_canvas_page' => FALSE, 'page_id' => NULL, 'title' => NULL],
  'pages' => ['total' => 0, 'listed' => 0, 'items' => []],
  'components' => ['by_source' => [], 'custom' => [], 'in_browser' => [], 'most_used' => [], 'unused_custom' => []],
  'content_templates' => [],
  'page_regions' => [],
  'patterns' => [],
];

if (!$enabled) {
  echo json_encode($output, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
  return;
}

// ---------------------------------------------------------------------------
// 2. Pages (canvas_page content entities)
// ---------------------------------------------------------------------------

$front_page = (string) $output['homepage']['front_page'];
$alias_manager = \Drupal::service('path_alias.manager');
$front_system_path = $front_page;
try {
  $front_system_path = $alias_manager->getPathByAlias($front_page);
}
catch (\Throwable $e) {
}

try {
  if ($entity_type_manager->hasDefinition('canvas_page')) {
    $storage = $entity_type_manager->getStorage('canvas_page');
    $count_query = function ($status = NULL) use ($storage) {
      $query = $storage->getQuery()->accessCheck(FALSE);
      if ($status !== NULL) {
        $query->condition('status', $status);
      }
      return (int) $query->count()->execute();
    };
    $output['summary']['pages_total'] = $count_query();
    $output['summary']['pages_published'] = $count_query(1);
    $output['summary']['pages_unpublished'] = $output['summary']['pages_total'] - $output['summary']['pages_published'];

    // All pages are loaded to count component usage; only the newest are listed.
    $ids = $storage->getQuery()->accessCheck(FALSE)->sort('changed', 'DESC')->execute();
    $listed = 0;
    foreach (array_chunk($ids, 50) as $chunk) {
      foreach ($storage->loadMultiple($chunk) as $page) {
        $tree = $page->hasField('components') ? $page->get('components')->getValue() : [];
        $components_count = $count_tree($tree);
        $unique = [];
        foreach ($tree as $item) {
          if (!empty($item['component_id'])) {
            $unique[$item['component_id']] = TRUE;
          }
        }

        $system_path = '/' . $page->toUrl()->getInternalPath();
        $url = $system_path;
        try {
          $url = $page->toUrl()->toString();
        }
        catch (\Throwable $e) {
        }
        $is_homepage = in_array($front_page, [$system_path, $url], TRUE) || $front_system_path === $system_path;
        if ($is_homepage) {
          $output['homepage']['is_canvas_page'] = TRUE;
          $output['homepage']['page_id'] = (int) $page->id();
          $output['homepage']['title'] = (string) $page->label();
        }

        if ($listed < $PAGES_LIMIT) {
          $output['pages']['items'][] = [
            'id' => (int) $page->id(),
            'title' => (string) $page->label(),
            'path' => $url,
            'published' => method_exists($page, 'isPublished') ? (bool) $page->isPublished() : NULL,
            'is_homepage' => $is_homepage,
            'components_count' => $components_count,
            'unique_components' => count($unique),
            'languages' => array_keys($page->getTranslationLanguages()),
            'created' => $page->hasField('created') && !$page->get('created')->isEmpty() ? date('Y-m-d', (int) $page->get('created')->value) : NULL,
            'changed' => $page->hasField('changed') && !$page->get('changed')->isEmpty() ? date('Y-m-d', (int) $page->get('changed')->value) : NULL,
          ];
          $listed++;
        }
      }
      $storage->resetCache($chunk);
    }
    $output['pages']['total'] = $output['summary']['pages_total'];
    $output['pages']['listed'] = $listed;
  }
}
catch (\Throwable $e) {
  $output['pages']['error'] = $e->getMessage();
}

// ---------------------------------------------------------------------------
// 3. Content templates, page regions, patterns (they also use components)
// ---------------------------------------------------------------------------

foreach ($load_all('content_template') as $id => $template) {
  $data = $template->toArray();
  $output['content_templates'][] = [
    'id' => $id,
    'entity_type' => $data['content_entity_type_id'] ?? NULL,
    'bundle' => $data['content_entity_type_bundle'] ?? NULL,
    'view_mode' => $data['content_entity_type_view_mode'] ?? NULL,
    'enabled' => (bool) $template->status(),
    'components_count' => $count_tree($data['component_tree'] ?? []),
  ];
}

foreach ($load_all('page_region') as $id => $region) {
  $data = $region->toArray();
  $output['page_regions'][] = [
    'id' => $id,
    'theme' => $data['theme'] ?? NULL,
    'region' => $data['region'] ?? NULL,
    'enabled' => (bool) $region->status(),
    'components_count' => $count_tree($data['component_tree'] ?? []),
  ];
}

foreach ($load_all('pattern') as $id => $pattern) {
  $data = $pattern->toArray();
  $output['patterns'][] = [
    'id' => $id,
    'label' => (string) $pattern->label(),
    'enabled' => (bool) $pattern->status(),
    'components_count' => $count_tree($data['component_tree'] ?? []),
  ];
}

// ---------------------------------------------------------------------------
// 4. Components
// ---------------------------------------------------------------------------

$by_source = [];
$custom = [];
$component_labels = [];
foreach ($load_all('component') as $id => $component) {
  $data = $component->toArray();
  $source = (string) ($data['source'] ?? 'unknown');
  $provider = $data['provider'] ?? NULL;
  $is_enabled = (bool) $component->status();
  $component_labels[$id] = (string) $component->label();

  if (!isset($by_source[$source])) {
    $by_source[$source] = [
      'source' => $source,
      'label' => $source_labels[$source]['label'] ?? $source,
      'description' => $source_labels[$source]['description'] ?? '',
      'total' => 0,
      'enabled' => 0,
      'providers' => [],
    ];
  }
  $by_source[$source]['total']++;
  if ($is_enabled) {
    $by_source[$source]['enabled']++;
  }
  $provider_key = $provider === NULL ? '(none)' : (string) $provider;
  $by_source[$source]['providers'][$provider_key] = ($by_source[$source]['providers'][$provider_key] ?? 0) + 1;

  // Custom code components: SDC from a custom theme or module.
  if ($source === 'sdc') {
    $origin = $extension_origin($provider);
    if ($origin['type'] === 'custom') {
      $custom[$id] = [
        'id' => $id,
        'label' => (string) $component->label(),
        'provider' => $provider,
        'provider_kind' => $origin['kind'],
        'enabled' => $is_enabled,
        'uses' => 0,
      ];
    }
  }
}

// In-browser code components (js_component config entities)
$in_browser = [];
foreach ($load_all('js_component') as $id => $js_component) {
  $data = $js_component->toArray();
  $in_browser[] = [
    'id' => $id,
    'label' => (string) $js_component->label(),
    'enabled' => (bool) $js_component->status(),
    'props_count' => is_array($data['props'] ?? NULL) ? count($data['props']) : 0,
    'slots_count' => is_array($data['slots'] ?? NULL) ? count($data['slots']) : 0,
    'has_css' => !empty($data['css']['original'] ?? $data['css'] ?? NULL),
    'uses' => $usage['js.' . $id] ?? 0,
  ];
}

// Usage numbers
arsort($usage);
$most_used = [];
foreach (array_slice($usage, 0, $USAGE_LIMIT, TRUE) as $component_id => $uses) {
  $most_used[] = [
    'id' => $component_id,
    'label' => $component_labels[$component_id] ?? $component_id,
    'uses' => $uses,
  ];
}

$unused_custom = [];
foreach ($custom as $id => $item) {
  $custom[$id]['uses'] = $usage[$id] ?? 0;
  if ($item['enabled'] && empty($usage[$id])) {
    $unused_custom[] = ['id' => $id, 'label' => $item['label'], 'provider' => $item['provider']];
  }
}

// Sort sources: biggest first; providers: biggest first
usort($by_source, function ($a, $b) {
  return $b['total'] <=> $a['total'];
});
foreach ($by_source as &$source_info) {
  arsort($source_info['providers']);
  $providers = [];
  foreach ($source_info['providers'] as $name => $count) {
    // origin: custom / contrib / core / unknown (where the module or theme lives)
    $providers[] = ['provider' => $name, 'count' => $count, 'origin' => $extension_origin($name === '(none)' ? NULL : $name)['type']];
  }
  $source_info['providers'] = $providers;
}
unset($source_info);

$output['components'] = [
  'by_source' => $by_source,
  'custom' => array_values($custom),
  'in_browser' => $in_browser,
  'most_used' => $most_used,
  'unused_custom' => $unused_custom,
];

// ---------------------------------------------------------------------------
// 5. Summary
// ---------------------------------------------------------------------------

$output['summary']['components_total'] = array_sum(array_column($by_source, 'total'));
$output['summary']['components_enabled'] = array_sum(array_column($by_source, 'enabled'));
$output['summary']['custom_code_components'] = count($custom);
$output['summary']['in_browser_code_components'] = count($in_browser);
$output['summary']['content_templates'] = count($output['content_templates']);
$output['summary']['page_regions'] = count($output['page_regions']);
$output['summary']['patterns'] = count($output['patterns']);
$output['summary']['folders'] = count($load_all('folder'));

echo json_encode($output, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR);
