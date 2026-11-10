#!/bin/bash
# Script: Analyze Menu Structure
# Purpose: Generate comprehensive JSON data about Drupal menu system
# Returns: JSON object with menus, structure, and Mermaid.js diagrams

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "{}"
    exit 0
fi

# Get the operation type (default: all_menus)
OPERATION="${1:-all_menus}"

# ============================================
# Function: Get all menus list
# ============================================
get_all_menus() {
    ddev drush eval "
        \$menus = \\Drupal::entityTypeManager()->getStorage('menu')->loadMultiple();
        \$result = [];
        foreach (\$menus as \$menu_id => \$menu) {
            \$menu_tree = \\Drupal::menuTree();
            \$parameters = \$menu_tree->getCurrentRouteMenuTreeParameters(\$menu_id);
            \$tree = \$menu_tree->load(\$menu_id, \$parameters);

            \$result[\$menu_id] = [
                'id' => \$menu_id,
                'label' => \$menu->label(),
                'description' => \$menu->getDescription(),
                'items_count' => count(\$tree)
            ];
        }
        echo json_encode(\$result, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo "{}"
}

# ============================================
# Function: Get main menu tree structure
# ============================================
get_main_menu_tree() {
    ddev drush eval "
        function build_menu_tree(\$items, \$depth = 0, \$max_depth = 5) {
            if (\$depth > \$max_depth) return [];

            \$result = [];
            foreach (\$items as \$item) {
                \$link = \$item->link;
                if (!\$link) continue;

                \$url_object = \$link->getUrlObject();
                \$menu_item = [
                    'title' => \$link->getTitle(),
                    'weight' => \$link->getWeight(),
                    'enabled' => \$link->isEnabled(),
                    'expanded' => \$link->isExpanded(),
                    'depth' => \$depth
                ];

                // Add URL info
                if (\$url_object->isRouted()) {
                    \$menu_item['route_name'] = \$url_object->getRouteName();
                    \$menu_item['type'] = 'internal';
                } else {
                    \$menu_item['uri'] = \$url_object->getUri();
                    \$menu_item['type'] = 'external';
                }

                // Process children recursively
                if (\$item->hasChildren && \$item->subtree) {
                    \$menu_item['children'] = build_menu_tree(\$item->subtree, \$depth + 1, \$max_depth);
                    \$menu_item['has_children'] = true;
                } else {
                    \$menu_item['has_children'] = false;
                }

                \$result[] = \$menu_item;
            }
            return \$result;
        }

        \$menu_tree = \\Drupal::menuTree();
        \$menu_name = 'main';
        \$parameters = \$menu_tree->getCurrentRouteMenuTreeParameters(\$menu_name);
        \$parameters->expandedParents = [];
        \$parameters->setMaxDepth(5);

        \$tree = \$menu_tree->load(\$menu_name, \$parameters);
        \$manipulators = [
            ['callable' => 'menu.default_tree_manipulators:checkAccess'],
            ['callable' => 'menu.default_tree_manipulators:generateIndexAndSort'],
        ];
        \$tree = \$menu_tree->transform(\$tree, \$manipulators);

        \$menu_tree_array = build_menu_tree(\$tree);
        echo json_encode(\$menu_tree_array, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo "[]"
}

# ============================================
# Function: Generate Mermaid.js diagram for main menu
# ============================================
generate_mermaid_diagram() {
    # Get main menu tree first
    MENU_JSON=$(get_main_menu_tree)

    # Use Python to generate Mermaid diagram from JSON
    python3 - 2>/dev/null <<EOF
import json
import sys
import re

def sanitize_mermaid_text(text):
    """Sanitize text for Mermaid.js - remove special characters"""
    # Replace ampersand with 'and'
    text = text.replace('&', 'and')
    # Replace problematic characters
    text = text.replace('<', '').replace('>', '')
    text = text.replace('"', '').replace("'", '')
    text = text.replace('~', 'approx ')
    text = text.replace('/', ' ')
    text = text.replace('\\\\', ' ')

    # Replace Polish characters with ASCII equivalents
    polish_chars = {
        'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n',
        'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
        'Ą': 'A', 'Ć': 'C', 'Ę': 'E', 'Ł': 'L', 'Ń': 'N',
        'Ó': 'O', 'Ś': 'S', 'Ź': 'Z', 'Ż': 'Z'
    }
    for pl_char, ascii_char in polish_chars.items():
        text = text.replace(pl_char, ascii_char)

    # Remove any other non-ASCII characters
    text = text.encode('ascii', 'ignore').decode('ascii')

    # Remove leading slashes and extra spaces
    text = re.sub(r'^\s*/', '', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

def generate_node_id(title, index, parent_id=''):
    """Generate unique node ID for Mermaid"""
    # Sanitize and create ID
    safe_title = re.sub(r'[^a-zA-Z0-9]', '', title)[:20]
    if parent_id:
        return f"{parent_id}_{safe_title}_{index}"
    return f"menu_{safe_title}_{index}"

def build_mermaid_tree(items, parent_id='MainMenu', level=0, max_level=3):
    """Recursively build Mermaid diagram structure"""
    if level > max_level or not items:
        return []

    lines = []

    for idx, item in enumerate(items):
        if not item.get('enabled', True):
            continue

        title = sanitize_mermaid_text(item.get('title', 'Untitled'))
        node_id = generate_node_id(title, idx, parent_id)

        # Add connection from parent to this node
        lines.append(f"    {parent_id} --> {node_id}[\"{title}\"]")

        # Process children if they exist
        if item.get('has_children', False) and item.get('children'):
            child_lines = build_mermaid_tree(
                item['children'],
                node_id,
                level + 1,
                max_level
            )
            lines.extend(child_lines)

    return lines

try:
    menu_data = json.loads('''${MENU_JSON}''')

    if not menu_data:
        print("graph TD")
        print("    MainMenu[Main Navigation Menu]")
        print("    MainMenu --> NoItems[No menu items found]")
        sys.exit(0)

    # Start building diagram
    diagram_lines = ["graph TD"]
    diagram_lines.append("    MainMenu[Main Navigation Menu]")
    diagram_lines.append("")

    # Build tree structure
    tree_lines = build_mermaid_tree(menu_data, 'MainMenu', 0, 3)
    diagram_lines.extend(tree_lines)

    # Add styling
    diagram_lines.append("")
    diagram_lines.append("    %% Styling")
    diagram_lines.append("    style MainMenu fill:#030a3d,color:#fff,stroke:#030a3d,stroke-width:2px")

    print("\\n".join(diagram_lines))

except Exception as e:
    print("graph TD", file=sys.stderr)
    print("    MainMenu[Main Navigation Menu]", file=sys.stderr)
    print(f"    MainMenu --> Error[Error: {str(e)}]", file=sys.stderr)
    sys.exit(1)
EOF
}

# ============================================
# Function: Get menu statistics
# ============================================
get_menu_statistics() {
    ddev drush eval "
        \$menus = \\Drupal::entityTypeManager()->getStorage('menu')->loadMultiple();
        \$menu_tree_service = \\Drupal::menuTree();

        \$stats = [
            'total_menus' => count(\$menus),
            'main_menu_items' => 0,
            'footer_menu_items' => 0,
            'max_depth' => 0,
            'menus_detail' => []
        ];

        function count_menu_depth(\$items, \$current_depth = 1) {
            \$max = \$current_depth;
            foreach (\$items as \$item) {
                if (\$item->hasChildren && \$item->subtree) {
                    \$child_depth = count_menu_depth(\$item->subtree, \$current_depth + 1);
                    \$max = max(\$max, \$child_depth);
                }
            }
            return \$max;
        }

        foreach (\$menus as \$menu_id => \$menu) {
            \$parameters = \$menu_tree_service->getCurrentRouteMenuTreeParameters(\$menu_id);
            \$tree = \$menu_tree_service->load(\$menu_id, \$parameters);

            \$items_count = count(\$tree);
            \$depth = count_menu_depth(\$tree);

            \$stats['menus_detail'][\$menu_id] = [
                'items_count' => \$items_count,
                'max_depth' => \$depth
            ];

            if (\$menu_id === 'main') {
                \$stats['main_menu_items'] = \$items_count;
            }
            if (\$menu_id === 'footer') {
                \$stats['footer_menu_items'] = \$items_count;
            }

            \$stats['max_depth'] = max(\$stats['max_depth'], \$depth);
        }

        echo json_encode(\$stats, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo "{}"
}

# ============================================
# Main execution based on operation type
# ============================================
case "$OPERATION" in
    all_menus)
        get_all_menus
        ;;
    main_menu_tree)
        get_main_menu_tree
        ;;
    mermaid_diagram)
        generate_mermaid_diagram
        ;;
    statistics)
        get_menu_statistics
        ;;
    *)
        echo "{\"error\": \"Unknown operation: $OPERATION\"}"
        exit 1
        ;;
esac
