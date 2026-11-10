#!/bin/bash
# Script: Analyze Entity Structure
# Purpose: Generate comprehensive JSON data about Drupal entity system
# Returns: JSON object with entity types, bundles, fields, and statistics
#
# How it works:
#   1. Scan custom modules on the host for entity classes (file system only)
#   2. Run scripts/php/entity_structure.php ONCE inside Drupal - it collects bundles,
#      fields, record counts, custom entity details and builds the Mermaid diagram
#
# Note: All Drupal data is collected with one drush call (one Drupal bootstrap).
#       Do not add "ddev drush" calls in loops here - extend the PHP file instead.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/drush_php.sh"

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "{}"
    exit 0
fi

# Function to detect custom entities from custom modules (file scan, no Drupal needed)
# Returns: JSON array of {module, class_name, entity_id, label}
find_custom_entities() {
    local found="[]"

    if [ ! -d "${DOCROOT}/modules/custom" ]; then
        echo "$found"
        return
    fi

    local dir entity_file module_name entity_name entity_id entity_label
    for dir in "${DOCROOT}/modules/custom"/*/; do
        if [ -d "${dir}src/Entity" ]; then
            for entity_file in "${dir}src/Entity"/*.php; do
                if [ -f "$entity_file" ]; then
                    # Check for entity annotations
                    if grep -q "@ContentEntityType\|@ConfigEntityType" "$entity_file" 2>/dev/null; then
                        module_name=$(basename "$dir")
                        entity_name=$(basename "$entity_file" .php)

                        # Extract entity ID from annotation
                        entity_id=$(grep -A 5 "@ContentEntityType\|@ConfigEntityType" "$entity_file" | grep "id = " | sed 's/.*id = "\([^"]*\)".*/\1/' | head -1)

                        # Extract label
                        entity_label=$(grep -A 5 "@ContentEntityType\|@ConfigEntityType" "$entity_file" | grep "label = " | sed 's/.*label = @Translation("\([^"]*\)").*/\1/' | head -1)

                        echo "    Found custom entity: $entity_id ($module_name)" >&2

                        found=$(echo "$found" | jq \
                            --arg module "$module_name" \
                            --arg name "$entity_name" \
                            --arg id "$entity_id" \
                            --arg label "$entity_label" \
                            '. + [{module: $module, class_name: $name, entity_id: $id, label: $label}]')
                    fi
                fi
            done
        fi
    done

    echo "$found"
}

echo "Detecting custom entities..." >&2
CUSTOM_ENTITIES=$(find_custom_entities)

echo "Collecting entity types, bundles, fields and statistics (one Drupal call)..." >&2
ARGS=$(jq -n --argjson custom "$CUSTOM_ENTITIES" '{custom_entities: $custom}')

drush_php "${SCRIPT_DIR}/php/entity_structure.php" "$ARGS" 2>/dev/null
