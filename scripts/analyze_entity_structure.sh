#!/bin/bash
# Script: Analyze Entity Structure
# Purpose: Generate comprehensive JSON data about Drupal entity system
# Returns: JSON object with entity types, bundles, fields, and statistics

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "{}"
    exit 0
fi

# Initialize result object
RESULT='{
    "entity_types": {},
    "custom_entities": [],
    "statistics": {},
    "mermaid_diagram": ""
}'

# Function to get all entity types
get_entity_types() {
    # Get entity types using Drush
    ENTITY_TYPES=$(ddev drush eval "
        \$entity_type_manager = \\Drupal::entityTypeManager();
        \$definitions = \$entity_type_manager->getDefinitions();
        \$types = [];
        foreach (\$definitions as \$entity_type_id => \$definition) {
            \$types[] = [
                'id' => \$entity_type_id,
                'label' => (string) \$definition->getLabel(),
                'class' => get_class(\$definition),
                'has_bundles' => \$definition->hasKey('bundle'),
                'base_table' => \$definition->getBaseTable(),
                'provider' => \$definition->getProvider()
            ];
        }
        echo json_encode(\$types);
    " 2>/dev/null)

    echo "$ENTITY_TYPES"
}

# Function to get bundles for an entity type
get_bundles() {
    local entity_type="$1"

    BUNDLES=$(ddev drush eval "
        \$entity_type = '$entity_type';
        \$bundle_info = \\Drupal::service('entity_type.bundle.info')->getBundleInfo(\$entity_type);
        echo json_encode(\$bundle_info);
    " 2>/dev/null)

    echo "$BUNDLES"
}

# Function to get field information for a bundle
get_fields() {
    local entity_type="$1"
    local bundle="$2"

    FIELDS=$(ddev drush eval "
        \$entity_type = '$entity_type';
        \$bundle = '$bundle';
        \$field_definitions = \\Drupal::service('entity_field.manager')->getFieldDefinitions(\$entity_type, \$bundle);
        \$fields = [];
        foreach (\$field_definitions as \$field_name => \$field_definition) {
            if (!\$field_definition->getFieldStorageDefinition()->isBaseField()) {
                \$storage = \$field_definition->getFieldStorageDefinition();
                \$fields[\$field_name] = [
                    'label' => (string) \$field_definition->getLabel(),
                    'type' => \$field_definition->getType(),
                    'required' => \$field_definition->isRequired(),
                    'cardinality' => \$storage->getCardinality(),
                    'description' => (string) \$field_definition->getDescription(),
                    'target_type' => method_exists(\$field_definition, 'getSetting') ? \$field_definition->getSetting('target_type') : null
                ];
            }
        }
        echo json_encode(\$fields);
    " 2>/dev/null)

    echo "$FIELDS"
}

# Function to get entity count statistics
get_entity_statistics() {
    local entity_type="$1"
    local bundle="$2"

    # Different queries based on entity type
    case "$entity_type" in
        node)
            TOTAL=$(ddev drush sql-query "SELECT COUNT(*) FROM node_field_data WHERE type='$bundle'" 2>/dev/null | head -1)
            LAST_YEAR=$(ddev drush sql-query "SELECT COUNT(*) FROM node_field_data WHERE type='$bundle' AND created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR))" 2>/dev/null | head -1)
            LAST_MONTH=$(ddev drush sql-query "SELECT COUNT(*) FROM node_field_data WHERE type='$bundle' AND created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH))" 2>/dev/null | head -1)
            ;;
        taxonomy_term)
            TOTAL=$(ddev drush sql-query "SELECT COUNT(*) FROM taxonomy_term_field_data WHERE vid='$bundle'" 2>/dev/null | head -1)
            LAST_YEAR="0"
            LAST_MONTH="0"
            ;;
        user)
            TOTAL=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data" 2>/dev/null | head -1)
            LAST_YEAR=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data WHERE created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR))" 2>/dev/null | head -1)
            LAST_MONTH=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data WHERE created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH))" 2>/dev/null | head -1)
            ;;
        media)
            TOTAL=$(ddev drush sql-query "SELECT COUNT(*) FROM media_field_data WHERE bundle='$bundle'" 2>/dev/null | head -1)
            LAST_YEAR=$(ddev drush sql-query "SELECT COUNT(*) FROM media_field_data WHERE bundle='$bundle' AND created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR))" 2>/dev/null | head -1)
            LAST_MONTH=$(ddev drush sql-query "SELECT COUNT(*) FROM media_field_data WHERE bundle='$bundle' AND created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH))" 2>/dev/null | head -1)
            ;;
        paragraph)
            TOTAL=$(ddev drush sql-query "SELECT COUNT(*) FROM paragraphs_item_field_data WHERE type='$bundle'" 2>/dev/null | head -1)
            LAST_YEAR="0"
            LAST_MONTH="0"
            ;;
        canvas_page)
            # Canvas entities don't have bundles, so ignore bundle parameter
            TOTAL=$(ddev drush sql-query "SELECT COUNT(*) FROM canvas_page" 2>/dev/null | head -1)
            LAST_YEAR=$(ddev drush sql-query "SELECT COUNT(*) FROM canvas_page WHERE created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR))" 2>/dev/null | head -1)
            LAST_MONTH=$(ddev drush sql-query "SELECT COUNT(*) FROM canvas_page WHERE created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH))" 2>/dev/null | head -1)
            ;;
        *)
            TOTAL="0"
            LAST_YEAR="0"
            LAST_MONTH="0"
            ;;
    esac

    # Remove any whitespace/newlines
    TOTAL=$(echo "$TOTAL" | tr -d '[:space:]')
    LAST_YEAR=$(echo "$LAST_YEAR" | tr -d '[:space:]')
    LAST_MONTH=$(echo "$LAST_MONTH" | tr -d '[:space:]')

    # Default to 0 if empty
    TOTAL=${TOTAL:-0}
    LAST_YEAR=${LAST_YEAR:-0}
    LAST_MONTH=${LAST_MONTH:-0}

    echo "{\"total\": $TOTAL, \"last_year\": $LAST_YEAR, \"last_month\": $LAST_MONTH}"
}

# Function to get detailed info about a custom entity
get_custom_entity_details() {
    local entity_id="$1"

    # Get comprehensive entity information via Drush
    ENTITY_INFO=$(ddev drush eval "
        \$entity_id = '$entity_id';
        try {
            \$entity_type = \\Drupal::entityTypeManager()->getDefinition(\$entity_id);
            \$result = [
                'base_table' => \$entity_type->getBaseTable(),
                'data_table' => \$entity_type->getDataTable(),
                'is_fieldable' => \$entity_type->entityClassImplements('\\Drupal\\Core\\Entity\\FieldableEntityInterface'),
                'has_created_field' => false,
                'table_schema' => [],
                'statistics' => ['total' => 0, 'last_year' => 0, 'last_month' => 0],
                'custom_fields' => []
            ];

            \$base_table = \$entity_type->getBaseTable();
            if (\$base_table) {
                // Get table schema
                \$connection = \\Drupal::database();
                \$schema = \$connection->schema();

                if (\$schema->tableExists(\$base_table)) {
                    // Get all column names and types
                    \$query = \$connection->query(\"SHOW COLUMNS FROM {\$base_table}\");
                    \$columns = [];
                    foreach (\$query as \$column) {
                        \$columns[] = [
                            'name' => \$column->Field,
                            'type' => \$column->Type,
                            'null' => \$column->Null,
                            'key' => \$column->Key,
                            'default' => \$column->Default,
                            'extra' => \$column->Extra
                        ];

                        // Check if created field exists
                        if (\$column->Field === 'created') {
                            \$result['has_created_field'] = true;
                        }
                    }
                    \$result['table_schema'] = \$columns;

                    // Get statistics
                    \$total = \$connection->query(\"SELECT COUNT(*) FROM {\$base_table}\")->fetchField();
                    \$result['statistics']['total'] = (int) \$total;

                    // If entity has created field, get time-based statistics
                    if (\$result['has_created_field']) {
                        \$last_year = \$connection->query(
                            \"SELECT COUNT(*) FROM {\$base_table} WHERE created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR))\"
                        )->fetchField();
                        \$result['statistics']['last_year'] = (int) \$last_year;

                        \$last_month = \$connection->query(
                            \"SELECT COUNT(*) FROM {\$base_table} WHERE created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH))\"
                        )->fetchField();
                        \$result['statistics']['last_month'] = (int) \$last_month;
                    }
                }
            }

            // Get custom fields if entity is fieldable
            if (\$entity_type->entityClassImplements('\\Drupal\\Core\\Entity\\FieldableEntityInterface')) {
                \$field_manager = \\Drupal::service('entity_field.manager');
                \$bundle_info = \\Drupal::service('entity_type.bundle.info')->getBundleInfo(\$entity_id);

                foreach (array_keys(\$bundle_info) as \$bundle) {
                    \$field_definitions = \$field_manager->getFieldDefinitions(\$entity_id, \$bundle);
                    foreach (\$field_definitions as \$field_name => \$field_definition) {
                        if (!\$field_definition->getFieldStorageDefinition()->isBaseField()) {
                            \$storage = \$field_definition->getFieldStorageDefinition();
                            \$result['custom_fields'][] = [
                                'bundle' => \$bundle,
                                'field_name' => \$field_name,
                                'label' => (string) \$field_definition->getLabel(),
                                'type' => \$field_definition->getType(),
                                'required' => \$field_definition->isRequired(),
                                'cardinality' => \$storage->getCardinality(),
                                'description' => (string) \$field_definition->getDescription()
                            ];
                        }
                    }
                }
            }

            echo json_encode(\$result);
        } catch (\\Exception \$e) {
            echo json_encode(['error' => \$e->getMessage()]);
        }
    " 2>/dev/null)

    echo "$ENTITY_INFO"
}

# Function to detect custom entities from custom modules
get_custom_entities() {
    if [ ! -d "${DOCROOT}/modules/custom" ]; then
        echo "[]"
        return
    fi

    CUSTOM_ENTITIES="[]"

    cd "${DOCROOT}/modules/custom" || return

    for dir in */; do
        if [ -d "$dir/src/Entity" ]; then
            for entity_file in "$dir/src/Entity"/*.php; do
                if [ -f "$entity_file" ]; then
                    # Check for entity annotations
                    if grep -q "@ContentEntityType\|@ConfigEntityType" "$entity_file" 2>/dev/null; then
                        module_name=$(basename "$dir")
                        entity_name=$(basename "$entity_file" .php)

                        # Extract entity ID from annotation
                        entity_id=$(grep -A 5 "@ContentEntityType\|@ConfigEntityType" "$entity_file" | grep "id = " | sed 's/.*id = "\([^"]*\)".*/\1/' | head -1)

                        # Extract label
                        entity_label=$(grep -A 5 "@ContentEntityType\|@ConfigEntityType" "$entity_file" | grep "label = " | sed 's/.*label = @Translation("\([^"]*\)").*/\1/' | head -1)

                        # Get detailed information about the entity
                        echo "    Analyzing custom entity: $entity_id..." >&2
                        ENTITY_DETAILS=$(get_custom_entity_details "$entity_id")

                        # Combine basic info with detailed info
                        ENTITY_OBJ=$(jq -n \
                            --arg module "$module_name" \
                            --arg name "$entity_name" \
                            --arg id "$entity_id" \
                            --arg label "$entity_label" \
                            --argjson details "$ENTITY_DETAILS" \
                            '{
                                module: $module,
                                class_name: $name,
                                entity_id: $id,
                                label: $label,
                                base_table: $details.base_table,
                                data_table: $details.data_table,
                                is_fieldable: $details.is_fieldable,
                                has_created_field: $details.has_created_field,
                                table_schema: $details.table_schema,
                                statistics: $details.statistics,
                                custom_fields: $details.custom_fields
                            }')

                        CUSTOM_ENTITIES=$(echo "$CUSTOM_ENTITIES" | jq --argjson entity "$ENTITY_OBJ" '. + [$entity]')
                    fi
                fi
            done
        fi
    done

    echo "$CUSTOM_ENTITIES"
}

# Function to generate Mermaid.js diagram
generate_mermaid_diagram() {
    local entity_data="$1"

    MERMAID="graph TB\n"
    MERMAID="${MERMAID}    %% Main Entity Types\n"
    MERMAID="${MERMAID}    Entities[Entity System]\n\n"

    # Add major entity types
    MERMAID="${MERMAID}    Entities --> Node[Content - Node]\n"
    MERMAID="${MERMAID}    Entities --> Taxonomy[Taxonomy Terms]\n"
    MERMAID="${MERMAID}    Entities --> User[Users]\n"
    MERMAID="${MERMAID}    Entities --> Media[Media]\n"
    MERMAID="${MERMAID}    Entities --> Paragraph[Paragraphs]\n"

    # Check if Canvas module is enabled
    CANVAS_CHECK=$(ddev drush eval "echo \Drupal::moduleHandler()->moduleExists('canvas') ? '1' : '0';" 2>/dev/null)
    if [ "$CANVAS_CHECK" = "1" ]; then
        MERMAID="${MERMAID}    Entities --> Canvas[Canvas Pages]\n"
    fi
    MERMAID="${MERMAID}\n"

    # Get content types and add to diagram
    CONTENT_TYPES=$(ddev drush eval "echo json_encode(array_keys(\Drupal::service('entity_type.bundle.info')->getBundleInfo('node')));" 2>/dev/null)
    if [ -n "$CONTENT_TYPES" ] && [ "$CONTENT_TYPES" != "[]" ]; then
        MERMAID="${MERMAID}    %% Content Types\n"
        TYPES_ARRAY=$(echo "$CONTENT_TYPES" | jq -r '.[]' 2>/dev/null)
        while IFS= read -r type; do
            if [ -n "$type" ]; then
                clean_type=$(echo "$type" | tr -d '[:space:]' | sed 's/[^a-zA-Z0-9_]/_/g')
                MERMAID="${MERMAID}    Node --> CT_${clean_type}[${type}]\n"
            fi
        done <<< "$TYPES_ARRAY"
        MERMAID="${MERMAID}\n"
    fi

    # Get taxonomies
    TAXONOMIES=$(ddev drush eval "echo json_encode(array_keys(\Drupal::service('entity_type.bundle.info')->getBundleInfo('taxonomy_term')));" 2>/dev/null)
    if [ -n "$TAXONOMIES" ] && [ "$TAXONOMIES" != "[]" ]; then
        MERMAID="${MERMAID}    %% Taxonomy Vocabularies\n"
        VOCABS_ARRAY=$(echo "$TAXONOMIES" | jq -r '.[]' 2>/dev/null)
        while IFS= read -r vid; do
            if [ -n "$vid" ]; then
                clean_vid=$(echo "$vid" | tr -d '[:space:]' | sed 's/[^a-zA-Z0-9_]/_/g')
                MERMAID="${MERMAID}    Taxonomy --> TAX_${clean_vid}[${vid}]\n"
            fi
        done <<< "$VOCABS_ARRAY"
        MERMAID="${MERMAID}\n"
    fi

    # Styling
    MERMAID="${MERMAID}    %% Styling\n"
    MERMAID="${MERMAID}    style Entities fill:#030a3d,color:#fff,stroke:#030a3d\n"
    MERMAID="${MERMAID}    style Node fill:#0039ff,color:#fff,stroke:#0039ff\n"
    MERMAID="${MERMAID}    style Taxonomy fill:#00e2d1,color:#030a3d,stroke:#0b9d86\n"
    MERMAID="${MERMAID}    style User fill:#f15a24,color:#fff,stroke:#f15a24\n"
    MERMAID="${MERMAID}    style Media fill:#0b9d86,color:#fff,stroke:#0b9d86\n"
    MERMAID="${MERMAID}    style Paragraph fill:#fdecc8,color:#030a3d,stroke:#f59e0b\n"

    # Add Canvas styling if enabled
    if [ "$CANVAS_CHECK" = "1" ]; then
        MERMAID="${MERMAID}    style Canvas fill:#5b6080,color:#fff,stroke:#5b6080\n"
    fi

    echo -e "$MERMAID"
}

# Main execution
main() {
    # Get all entity types
    echo "Collecting entity types..." >&2
    ENTITY_TYPES=$(get_entity_types)

    # Focus on main entity types for detailed analysis
    MAIN_ENTITIES=("node" "taxonomy_term" "user" "media" "paragraph")

    FINAL_DATA='{}'

    # Check if Canvas module is enabled and add canvas_page entity
    CANVAS_ENABLED=$(ddev drush eval "echo \Drupal::moduleHandler()->moduleExists('canvas') ? '1' : '0';" 2>/dev/null)
    if [ "$CANVAS_ENABLED" = "1" ]; then
        echo "Canvas module detected - adding canvas_page entity" >&2
        MAIN_ENTITIES+=("canvas_page")
    fi

    for entity_type in "${MAIN_ENTITIES[@]}"; do
        echo "Processing $entity_type..." >&2

        # Get bundles
        BUNDLES=$(get_bundles "$entity_type")

        if [ "$BUNDLES" != "null" ] && [ "$BUNDLES" != "{}" ] && [ -n "$BUNDLES" ]; then
            # Process each bundle
            BUNDLE_KEYS=$(echo "$BUNDLES" | jq -r 'keys[]' 2>/dev/null)

            while IFS= read -r bundle; do
                if [ -n "$bundle" ]; then
                    echo "  Processing bundle: $bundle" >&2

                    # Get fields
                    FIELDS=$(get_fields "$entity_type" "$bundle")

                    # Get statistics
                    STATS=$(get_entity_statistics "$entity_type" "$bundle")

                    # Combine data
                    BUNDLE_DATA=$(jq -n \
                        --arg bundle "$bundle" \
                        --argjson fields "$FIELDS" \
                        --argjson stats "$STATS" \
                        '{
                            bundle: $bundle,
                            fields: $fields,
                            statistics: $stats
                        }')

                    # Add to entity type data
                    FINAL_DATA=$(echo "$FINAL_DATA" | jq \
                        --arg entity "$entity_type" \
                        --argjson bundle_data "$BUNDLE_DATA" \
                        '.entity_types[$entity] += [$bundle_data]')
                fi
            done <<< "$BUNDLE_KEYS"
        fi
    done

    # Get custom entities
    echo "Detecting custom entities..." >&2
    CUSTOM_ENTITIES=$(get_custom_entities)
    FINAL_DATA=$(echo "$FINAL_DATA" | jq --argjson custom "$CUSTOM_ENTITIES" '.custom_entities = $custom')

    # Generate Mermaid diagram
    echo "Generating Mermaid diagram..." >&2
    MERMAID=$(generate_mermaid_diagram "$FINAL_DATA")
    FINAL_DATA=$(echo "$FINAL_DATA" | jq --arg diagram "$MERMAID" '.mermaid_diagram = $diagram')

    # Calculate overall statistics
    TOTAL_NODES=$(ddev drush sql-query "SELECT COUNT(*) FROM node_field_data" 2>/dev/null | head -1 | tr -d '[:space:]')
    TOTAL_TERMS=$(ddev drush sql-query "SELECT COUNT(*) FROM taxonomy_term_field_data" 2>/dev/null | head -1 | tr -d '[:space:]')
    TOTAL_USERS=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data" 2>/dev/null | head -1 | tr -d '[:space:]')
    TOTAL_MEDIA=$(ddev drush sql-query "SELECT COUNT(*) FROM media_field_data" 2>/dev/null | head -1 | tr -d '[:space:]')

    # Check Canvas entities if module is enabled
    TOTAL_CANVAS="0"
    if [ "$CANVAS_ENABLED" = "1" ]; then
        TOTAL_CANVAS=$(ddev drush sql-query "SELECT COUNT(*) FROM canvas_page" 2>/dev/null | head -1 | tr -d '[:space:]')
    fi

    OVERALL_STATS=$(jq -n \
        --arg nodes "${TOTAL_NODES:-0}" \
        --arg terms "${TOTAL_TERMS:-0}" \
        --arg users "${TOTAL_USERS:-0}" \
        --arg media "${TOTAL_MEDIA:-0}" \
        --arg canvas "${TOTAL_CANVAS:-0}" \
        '{
            total_nodes: ($nodes | tonumber),
            total_taxonomy_terms: ($terms | tonumber),
            total_users: ($users | tonumber),
            total_media: ($media | tonumber),
            total_canvas_pages: ($canvas | tonumber)
        }')

    FINAL_DATA=$(echo "$FINAL_DATA" | jq --argjson stats "$OVERALL_STATS" '.overall_statistics = $stats')

    echo "$FINAL_DATA"
}

# Run main function
main
