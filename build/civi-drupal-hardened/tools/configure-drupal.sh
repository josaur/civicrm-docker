#!/bin/sh
# Configures a freshly installed Drupal instance for CiviCRM. Idempotent, safe to run after every install.
#
#  - Serve CiviCRM pages in the admin theme (Claro). In the front-end theme (Olivero) the content is
#    limited to a narrow column.
#  - Add a main menu entry "CiviCRM" so CiviCRM is reachable from the front page.
#
# Usage inside the container:  sh /opt/tools/configure-drupal.sh
set -eu
cd /opt/drupal/web
THEME="${CIVICRM_THEME:-claro}"

# The civicrmtheme module selects the theme for all paths below /civicrm
drush pm:list --status=enabled --type=module --field=name 2>/dev/null | grep -qx civicrmtheme \
  || drush en civicrmtheme -y
drush config:set civicrmtheme.settings admin_theme "$THEME" -y
drush config:set civicrmtheme.settings public_theme "$THEME" -y

# Main menu link to CiviCRM. CiviCRM checks permissions inside the page, so the link is visible
# to everybody; visitors without access are sent to the login.
drush php:eval '
use Drupal\menu_link_content\Entity\MenuLinkContent;
$storage = \Drupal::entityTypeManager()->getStorage("menu_link_content");
if (!$storage->loadByProperties(["menu_name" => "main", "link__uri" => "internal:/civicrm"])) {
  MenuLinkContent::create([
    "title" => "CiviCRM",
    "link" => ["uri" => "internal:/civicrm"],
    "menu_name" => "main",
    "weight" => -10,
    "enabled" => TRUE,
  ])->save();
  echo "Menu link CiviCRM created\n";
}
else {
  echo "Menu link CiviCRM exists\n";
}'

drush cache:rebuild
echo "Drupal configured for CiviCRM (theme: $THEME)."
