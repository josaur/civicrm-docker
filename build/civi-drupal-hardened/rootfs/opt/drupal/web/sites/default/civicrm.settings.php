<?php

/**
 * CiviCRM settings for the immutable image (Drupal 11).
 *
 * All values come from environment variables. Nothing of this is stored in the image.
 * Only /data (volume) and /tmp (tmpfs) are writable.
 */

global $civicrm_root, $civicrm_setting, $civicrm_paths;

/**
 * @param string $name
 * @return string
 */
$civiEnv = static function (string $name, ?string $default = null): string {
  $v = getenv($name);
  if ($v === false || $v === '') {
    // Secrets can also come from a file $CIVI_MOUNT_DIR/<name in lower case with dashes>,
    // for example a mounted Kubernetes Secret (CIVICRM_SITE_KEY -> civicrm-site-key).
    $dir = getenv('CIVI_MOUNT_DIR');
    if ($dir !== false && $dir !== '') {
      $file = rtrim($dir, '/') . '/' . strtolower(str_replace('_', '-', $name));
      if (is_readable($file)) {
        return rtrim((string) file_get_contents($file), "\r\n");
      }
    }
    if ($default === null) {
      throw new \RuntimeException("Environment variable $name is not set.");
    }
    return $default;
  }
  return $v;
};

$dsn = sprintf(
  'mysql://%s:%s@%s:%s/%s?new_link=true',
  rawurlencode($civiEnv('CIVICRM_DB_USER', getenv('DRUPAL_DB_USER') ?: 'drupal')),
  rawurlencode($civiEnv('CIVICRM_DB_PASSWORD', $civiEnv('DRUPAL_DB_PASSWORD', ''))),
  $civiEnv('CIVICRM_DB_HOST', getenv('DRUPAL_DB_HOST') ?: '127.0.0.1'),
  $civiEnv('CIVICRM_DB_PORT', getenv('DRUPAL_DB_PORT') ?: '3306'),
  $civiEnv('CIVICRM_DB_NAME', getenv('DRUPAL_DB_NAME') ?: 'drupal'),
);

define('CIVICRM_UF', 'Drupal8');
define('CIVICRM_UF_DSN', $dsn);
define('CIVICRM_DSN', $dsn);
define('CIVICRM_LOGGING_DSN', CIVICRM_DSN);
define('CIVICRM_UF_BASEURL', rtrim($civiEnv('CIVICRM_BASE_URL'), '/'));

// Secrets: required, no defaults.
define('CIVICRM_SITE_KEY', $civiEnv('CIVICRM_SITE_KEY'));
define('CIVICRM_CRED_KEYS', $civiEnv('CIVICRM_CRED_KEYS'));
define('CIVICRM_SIGN_KEYS', $civiEnv('CIVICRM_SIGN_KEYS'));
define('CIVICRM_DEPLOY_ID', $civiEnv('CIVICRM_DEPLOY_ID', ''));

define('CIVICRM_DOMAIN_ID', 1);
define('CIVICRM_MAIL_SMARTY', 0);
define('CIVICRM_DEDUPE_OPTIMIZER', FALSE);
define('CIVICRM_DEADLOCK_RETRIES', 3);
define('CIVICRM_PSR16_STRICT', FALSE);

// File and cache paths
$civicrm_root = '/opt/drupal/vendor/civicrm/civicrm-core/';
$civicrm_paths['civicrm.files']['url'] = CIVICRM_UF_BASEURL . '/sites/default/files/civicrm';
$civicrm_paths['civicrm.files']['path'] = '/data/public/civicrm';
$civicrm_paths['civicrm.private']['path'] = '/data/private/civicrm';
$civicrm_paths['civicrm.l10n']['path'] = '/data/private/civicrm/l10n';

// Extensions live in the code tree, not in the data volume (PHP does not run below /data and sites/*/files).
// The directory is empty in the image; a deployment mounts the extensions there read-only
// (for example filled by an init container).
$civicrm_setting['Directory Preferences']['extensionsDir'] = '/opt/drupal/web/sites/default/ext';
$civicrm_setting['URL Preferences']['extensionsURL'] = CIVICRM_UF_BASEURL . '/sites/default/ext';

// Smarty compiled templates are ephemeral (tmpfs): not in the volume, not in the image.
define('CIVICRM_TEMPLATE_COMPILEDIR', '/tmp/civicrm/templates_c');
// Code is immutable: templates do not need to be checked for changes.
define('CIVICRM_TEMPLATE_COMPILE_CHECK', FALSE);

define('CIVICRM_DB_CACHE_CLASS', 'ArrayCache');
define('CIVICRM_DB_CACHE_HOST', 'localhost');
define('CIVICRM_DB_CACHE_PORT', 11211);
define('CIVICRM_DB_CACHE_SOCKET', '');
define('CIVICRM_DB_CACHE_PASSWORD', '');
define('CIVICRM_DB_CACHE_TIMEOUT', 3600);
define('CIVICRM_DB_CACHE_PREFIX', '');

define('CIVICRM_EXCLUDE_DIRS_PATTERN', '@/(\.|node_modules|js/|css/|bower_components|packages/|sites/default/files/private)@');

$include_path = '.' . PATH_SEPARATOR .
  $civicrm_root . PATH_SEPARATOR .
  $civicrm_root . DIRECTORY_SEPARATOR . 'packages' . PATH_SEPARATOR .
  get_include_path();
if (set_include_path($include_path) === FALSE) {
  echo 'Could not set the include path';
  exit();
}

define('CIVICRM_CLEANURL', 1);

// CiviCRM needs at least 128 MB.
$memLimitString = trim(ini_get('memory_limit'));
$memLimitUnit = strtolower(substr($memLimitString, -1));
$memLimit = (int) $memLimitString;
switch ($memLimitUnit) {
  case 'g': $memLimit *= 1024;
  case 'm': $memLimit *= 1024;
  case 'k': $memLimit *= 1024;
}
if ($memLimit >= 0 && $memLimit < 134217728) {
  ini_set('memory_limit', '128M');
}

require_once 'CRM/Core/ClassLoader.php';
CRM_Core_ClassLoader::singleton()->register();
