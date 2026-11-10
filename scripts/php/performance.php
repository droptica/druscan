<?php
// Backend performance data that needs Drupal - collected in ONE Drupal bootstrap.
// Run by: scripts/analyze_performance.sh (through drush_php).
// Output: JSON used by the cache, database, aggregation and image parts of the analysis.

$db = \Drupal::database();
$schema = $db->schema();
$performance = \Drupal::config('system.performance');

// Part that fails returns the default value and does not break the others.
$safe = function (callable $callback, $default) {
  try {
    return $callback();
  }
  catch (\Throwable $e) {
    return $default;
  }
};

// Config value as text: "true", "false", number as string, or "null" when not set.
$config_text = function ($key) use ($performance) {
  $value = $performance->get($key);
  if ($value === NULL) {
    return 'null';
  }
  if (is_bool($value)) {
    return $value ? 'true' : 'false';
  }
  return (string) $value;
};

// Number of indexes on a table (0 when the table does not exist).
$count_indexes = function ($table) use ($db, $schema) {
  if (!$schema->tableExists($table)) {
    return 0;
  }
  $names = [];
  foreach ($db->query('SHOW INDEX FROM {' . $table . '}') as $row) {
    $names[$row->Key_name] = TRUE;
  }
  return count($names);
};

$output = [
  'page_cache_max_age' => (int) $performance->get('cache.page.max_age'),
  'css_preprocess' => $config_text('css.preprocess'),
  'js_preprocess' => $config_text('js.preprocess'),

  'cache_bins' => $safe(function () {
    return array_keys(\Drupal\Core\Cache\Cache::getBins());
  }, []),

  'node_field_data_indexes' => $safe(function () use ($count_indexes) {
    return $count_indexes('node_field_data');
  }, 0),
  'users_field_data_indexes' => $safe(function () use ($count_indexes) {
    return $count_indexes('users_field_data');
  }, 0),
  'taxonomy_term_field_data_indexes' => $safe(function () use ($count_indexes) {
    return $count_indexes('taxonomy_term_field_data');
  }, 0),

  // Tables without a primary key (bad for replication and performance)
  'tables_without_primary_key' => $safe(function () use ($db) {
    $tables = [];
    $query = $db->query("
      SELECT t.TABLE_NAME AS table_name
      FROM information_schema.TABLES t
      WHERE t.TABLE_SCHEMA = DATABASE()
        AND t.TABLE_TYPE = 'BASE TABLE'
        AND t.TABLE_NAME NOT IN (
          SELECT c.TABLE_NAME FROM information_schema.TABLE_CONSTRAINTS c
          WHERE c.CONSTRAINT_TYPE = 'PRIMARY KEY' AND c.TABLE_SCHEMA = DATABASE()
        )
      ORDER BY t.TABLE_NAME
    ");
    foreach ($query as $row) {
      $tables[] = $row->table_name;
    }
    return $tables;
  }, []),

  // 20 largest tables (potential bottlenecks)
  'largest_tables' => $safe(function () use ($db) {
    $tables = [];
    $query = $db->query("
      SELECT TABLE_NAME AS table_name,
             ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb,
             TABLE_ROWS AS row_count
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
      ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
      LIMIT 20
    ");
    foreach ($query as $row) {
      $tables[] = [
        'table_name' => $row->table_name,
        'size_mb' => (float) $row->size_mb,
        'row_count' => (int) $row->row_count,
      ];
    }
    return $tables;
  }, []),

  'image_styles_count' => $safe(function () {
    return count(\Drupal::configFactory()->listAll('image.style.'));
  }, 0),
];

echo json_encode($output, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR);
