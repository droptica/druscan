<?php
// Entity structure analysis - all data collected in ONE Drupal bootstrap.
// Run by: scripts/analyze_entity_structure.sh (through drush_php).
//
// Input ($druscan_args):
//   custom_entities - list of ['module', 'class_name', 'entity_id', 'label'] found in
//                     custom modules by the shell script (file scan on the host)
// Output: JSON with entity_types, custom_entities, mermaid_diagram, overall_statistics

$db = \Drupal::database();
$schema = $db->schema();
$entity_type_manager = \Drupal::entityTypeManager();
$bundle_info_service = \Drupal::service('entity_type.bundle.info');
$field_manager = \Drupal::service('entity_field.manager');
$canvas_enabled = \Drupal::moduleHandler()->moduleExists('canvas');

$since_year = 'UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR))';
$since_month = 'UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH))';
$zero_stats = ['total' => 0, 'last_year' => 0, 'last_month' => 0];

// Count rows of a table. With $bundle_column: one query with GROUP BY, result keyed by bundle.
// Without it: result has one row under key '*'. Missing table or SQL error = empty result.
$count_rows = function ($table, $bundle_column, $has_created) use ($db, $schema, $since_year, $since_month) {
  $result = [];
  try {
    if (!$schema->tableExists($table)) {
      return $result;
    }
    $select = 'COUNT(*) AS total';
    if ($has_created) {
      $select .= ", SUM(created > $since_year) AS last_year, SUM(created > $since_month) AS last_month";
    }
    if ($bundle_column) {
      $rows = $db->query("SELECT $bundle_column AS bundle, $select FROM {" . $table . "} GROUP BY $bundle_column");
    }
    else {
      $rows = $db->query("SELECT '*' AS bundle, $select FROM {" . $table . "}");
    }
    foreach ($rows as $row) {
      $result[(string) $row->bundle] = [
        'total' => (int) $row->total,
        'last_year' => $has_created ? (int) $row->last_year : 0,
        'last_month' => $has_created ? (int) $row->last_month : 0,
      ];
    }
  }
  catch (\Exception $e) {
    // Keep what we have (same as before: failed query = 0).
  }
  return $result;
};

// Non-base fields of one bundle.
$get_fields = function ($entity_type, $bundle, $with_target_type) use ($field_manager) {
  $fields = [];
  foreach ($field_manager->getFieldDefinitions($entity_type, $bundle) as $field_name => $field_definition) {
    $storage = $field_definition->getFieldStorageDefinition();
    if ($storage->isBaseField()) {
      continue;
    }
    $field = [
      'label' => (string) $field_definition->getLabel(),
      'type' => $field_definition->getType(),
      'required' => $field_definition->isRequired(),
      'cardinality' => $storage->getCardinality(),
      'description' => (string) $field_definition->getDescription(),
    ];
    if ($with_target_type) {
      $field['target_type'] = method_exists($field_definition, 'getSetting') ? $field_definition->getSetting('target_type') : NULL;
    }
    $fields[$field_name] = $field;
  }
  return $fields;
};

// ---------------------------------------------------------------------------
// 1. Main entity types: bundles, fields, record counts
// ---------------------------------------------------------------------------

// entity type => [table, bundle column (NULL = no bundles in table), has "created" column]
$main_entities = [
  'node' => ['node_field_data', 'type', TRUE],
  'taxonomy_term' => ['taxonomy_term_field_data', 'vid', FALSE],
  'user' => ['users_field_data', NULL, TRUE],
  'media' => ['media_field_data', 'bundle', TRUE],
  'paragraph' => ['paragraphs_item_field_data', 'type', FALSE],
];
if ($canvas_enabled) {
  $main_entities['canvas_page'] = ['canvas_page', NULL, TRUE];
}

$entity_types = [];
$bundle_names = [];
foreach ($main_entities as $entity_type => $table_info) {
  $bundle_names[$entity_type] = [];
  if (!$entity_type_manager->hasDefinition($entity_type)) {
    continue;
  }
  list($table, $bundle_column, $has_created) = $table_info;
  $bundles = array_map('strval', array_keys($bundle_info_service->getBundleInfo($entity_type)));
  $bundle_names[$entity_type] = $bundles;
  if (!$bundles) {
    continue;
  }
  $counts = $count_rows($table, $bundle_column, $has_created);

  $sorted_bundles = $bundles;
  sort($sorted_bundles, SORT_STRING);
  foreach ($sorted_bundles as $bundle) {
    $stats = $bundle_column ? ($counts[$bundle] ?? $zero_stats) : ($counts['*'] ?? $zero_stats);
    $entity_types[$entity_type][] = [
      'bundle' => $bundle,
      'fields' => $get_fields($entity_type, $bundle, TRUE),
      'statistics' => $stats,
    ];
  }
}

// ---------------------------------------------------------------------------
// 2. Custom entities (found in custom modules by the shell script)
// ---------------------------------------------------------------------------

$get_custom_entity_details = function ($entity_id) use ($db, $schema, $entity_type_manager, $bundle_info_service, $get_fields, $since_year, $since_month) {
  $entity_type = $entity_type_manager->getDefinition($entity_id);
  $is_fieldable = $entity_type->entityClassImplements('\Drupal\Core\Entity\FieldableEntityInterface');
  $result = [
    'base_table' => $entity_type->getBaseTable(),
    'data_table' => $entity_type->getDataTable(),
    'is_fieldable' => $is_fieldable,
    'has_created_field' => FALSE,
    'table_schema' => [],
    'statistics' => ['total' => 0, 'last_year' => 0, 'last_month' => 0],
    'custom_fields' => [],
  ];

  $base_table = $entity_type->getBaseTable();
  if ($base_table && $schema->tableExists($base_table)) {
    $table = '{' . $base_table . '}';
    foreach ($db->query("SHOW COLUMNS FROM $table") as $column) {
      $result['table_schema'][] = [
        'name' => $column->Field,
        'type' => $column->Type,
        'null' => $column->Null,
        'key' => $column->Key,
        'default' => $column->Default,
        'extra' => $column->Extra,
      ];
      if ($column->Field === 'created') {
        $result['has_created_field'] = TRUE;
      }
    }

    $result['statistics']['total'] = (int) $db->query("SELECT COUNT(*) FROM $table")->fetchField();
    if ($result['has_created_field']) {
      $result['statistics']['last_year'] = (int) $db->query("SELECT COUNT(*) FROM $table WHERE created > $since_year")->fetchField();
      $result['statistics']['last_month'] = (int) $db->query("SELECT COUNT(*) FROM $table WHERE created > $since_month")->fetchField();
    }
  }

  if ($is_fieldable) {
    foreach (array_keys($bundle_info_service->getBundleInfo($entity_id)) as $bundle) {
      foreach ($get_fields($entity_id, $bundle, FALSE) as $field_name => $field) {
        $result['custom_fields'][] = [
          'bundle' => $bundle,
          'field_name' => $field_name,
          'label' => $field['label'],
          'type' => $field['type'],
          'required' => $field['required'],
          'cardinality' => $field['cardinality'],
          'description' => $field['description'],
        ];
      }
    }
  }

  return $result;
};

$custom_entities = [];
$found_entities = is_array($druscan_args) ? ($druscan_args['custom_entities'] ?? []) : [];
foreach ($found_entities as $found) {
  $entity_id = (string) ($found['entity_id'] ?? '');
  try {
    $details = $get_custom_entity_details($entity_id);
  }
  catch (\Exception $e) {
    // Entity not registered in Drupal (e.g., module disabled): details stay empty.
    $details = [];
  }
  $custom_entities[] = [
    'module' => (string) ($found['module'] ?? ''),
    'class_name' => (string) ($found['class_name'] ?? ''),
    'entity_id' => $entity_id,
    'label' => (string) ($found['label'] ?? ''),
    'base_table' => $details['base_table'] ?? NULL,
    'data_table' => $details['data_table'] ?? NULL,
    'is_fieldable' => $details['is_fieldable'] ?? NULL,
    'has_created_field' => $details['has_created_field'] ?? NULL,
    'table_schema' => $details['table_schema'] ?? NULL,
    'statistics' => $details['statistics'] ?? NULL,
    'custom_fields' => $details['custom_fields'] ?? NULL,
  ];
}

// ---------------------------------------------------------------------------
// 3. Mermaid diagram
// ---------------------------------------------------------------------------

$clean_id = function ($name) {
  return preg_replace('/[^a-zA-Z0-9_]/', '_', preg_replace('/\s+/', '', $name));
};

$mermaid = "graph TB\n";
$mermaid .= "    %% Main Entity Types\n";
$mermaid .= "    Entities[Entity System]\n\n";
$mermaid .= "    Entities --> Node[Content - Node]\n";
$mermaid .= "    Entities --> Taxonomy[Taxonomy Terms]\n";
$mermaid .= "    Entities --> User[Users]\n";
$mermaid .= "    Entities --> Media[Media]\n";
$mermaid .= "    Entities --> Paragraph[Paragraphs]\n";
if ($canvas_enabled) {
  $mermaid .= "    Entities --> Canvas[Canvas Pages]\n";
}
$mermaid .= "\n";

if ($bundle_names['node']) {
  $mermaid .= "    %% Content Types\n";
  foreach ($bundle_names['node'] as $type) {
    $mermaid .= "    Node --> CT_" . $clean_id($type) . "[" . $type . "]\n";
  }
  $mermaid .= "\n";
}

if ($bundle_names['taxonomy_term']) {
  $mermaid .= "    %% Taxonomy Vocabularies\n";
  foreach ($bundle_names['taxonomy_term'] as $vid) {
    $mermaid .= "    Taxonomy --> TAX_" . $clean_id($vid) . "[" . $vid . "]\n";
  }
  $mermaid .= "\n";
}

$mermaid .= "    %% Styling\n";
$mermaid .= "    style Entities fill:#030a3d,color:#fff,stroke:#030a3d\n";
$mermaid .= "    style Node fill:#0039ff,color:#fff,stroke:#0039ff\n";
$mermaid .= "    style Taxonomy fill:#00e2d1,color:#030a3d,stroke:#0b9d86\n";
$mermaid .= "    style User fill:#f15a24,color:#fff,stroke:#f15a24\n";
$mermaid .= "    style Media fill:#0b9d86,color:#fff,stroke:#0b9d86\n";
$mermaid .= "    style Paragraph fill:#fdecc8,color:#030a3d,stroke:#f59e0b\n";
if ($canvas_enabled) {
  $mermaid .= "    style Canvas fill:#5b6080,color:#fff,stroke:#5b6080\n";
}
$mermaid = rtrim($mermaid, "\n");

// ---------------------------------------------------------------------------
// 4. Overall statistics
// ---------------------------------------------------------------------------

$total_rows = function ($table) use ($count_rows) {
  $counts = $count_rows($table, NULL, FALSE);
  return $counts['*']['total'] ?? 0;
};

$overall_statistics = [
  'total_nodes' => $total_rows('node_field_data'),
  'total_taxonomy_terms' => $total_rows('taxonomy_term_field_data'),
  'total_users' => $total_rows('users_field_data'),
  'total_media' => $total_rows('media_field_data'),
  'total_canvas_pages' => $canvas_enabled ? $total_rows('canvas_page') : 0,
];

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

$output = [];
if ($entity_types) {
  $output['entity_types'] = $entity_types;
}
$output['custom_entities'] = $custom_entities;
$output['mermaid_diagram'] = $mermaid;
$output['overall_statistics'] = $overall_statistics;

echo json_encode($output, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR);
