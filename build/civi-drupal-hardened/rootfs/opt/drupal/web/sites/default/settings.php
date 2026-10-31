<?php

/**
 * Drupal settings for the immutable image.
 *
 * Everything variable comes from environment variables (Kubernetes Secret/ConfigMap).
 * The root filesystem is read-only; only /data (volume) and /tmp (tmpfs) are writable.
 */

/**
 * Reads a secret from the environment variable NAME or, if unset, from the file
 * $CIVI_MOUNT_DIR/<name in lower case with dashes> (for example DRUPAL_DB_PASSWORD ->
 * drupal-db-password, a mounted Kubernetes Secret). Files keep secrets out of the container environment.
 */
$drupalSecret = static function (string $name): string {
  $v = getenv($name);
  if ($v !== false && $v !== '') {
    return $v;
  }
  $dir = getenv('CIVI_MOUNT_DIR');
  if ($dir !== false && $dir !== '') {
    $file = rtrim($dir, '/') . '/' . strtolower(str_replace('_', '-', $name));
    if (is_readable($file)) {
      return rtrim((string) file_get_contents($file), "\r\n");
    }
  }
  return '';
};

$databases['default']['default'] = [
  'driver' => 'mysql',
  'host' => getenv('DRUPAL_DB_HOST') ?: '127.0.0.1',
  'port' => getenv('DRUPAL_DB_PORT') ?: '3306',
  'database' => getenv('DRUPAL_DB_NAME') ?: 'drupal',
  'username' => getenv('DRUPAL_DB_USER') ?: 'drupal',
  'password' => $drupalSecret('DRUPAL_DB_PASSWORD'),
  'prefix' => '',
  'collation' => 'utf8mb4_general_ci',
  'namespace' => 'Drupal\\mysql\\Driver\\Database\\mysql',
  'autoload' => 'core/modules/mysql/src/Driver/Database/mysql/',
];

$settings['hash_salt'] = $drupalSecret('DRUPAL_HASH_SALT');
if ($settings['hash_salt'] === '') {
  throw new \RuntimeException('DRUPAL_HASH_SALT is not set (environment variable or file in CIVI_MOUNT_DIR).');
}

// Only the configured host name(s), comma separated.
$trusted = array_filter(array_map('trim', explode(',', getenv('DRUPAL_TRUSTED_HOSTS') ?: '')));
$settings['trusted_host_patterns'] = array_map(
  fn($h) => '^' . preg_quote($h, '/') . '$',
  $trusted ?: ['localhost', '127.0.0.1'],
);

// Files: only below /data (persistent volume).
$settings['file_public_path'] = 'sites/default/files';          // symlink -> /data/public
$settings['file_private_path'] = '/data/private';
$settings['config_sync_directory'] = '/data/private/config';

// Compiled Twig/PHP files go to tmpfs: not into the code tree and not persistent.
$settings['php_storage']['default']['directory'] = '/tmp/drupal-php';
$settings['php_storage']['twig']['directory'] = '/tmp/drupal-php';

// Code is immutable: no permission hardening attempts, no updates through the web UI.
$settings['skip_permissions_hardening'] = TRUE;
$settings['update_free_access'] = FALSE;
$settings['allow_authorize_operations'] = FALSE;

// Behind an ingress/proxy: take client IP and scheme from X-Forwarded-*.
$settings['reverse_proxy'] = TRUE;
$settings['reverse_proxy_addresses'] = array_filter(array_map('trim', explode(',', getenv('DRUPAL_REVERSE_PROXY_ADDRESSES') ?: '')));

// Do not show errors to visitors.
$config['system.logging']['error_level'] = 'hide';

// OpenID Connect login (module openid_connect 8.x-1.x, generic client, redirect /openid-connect/generic). The endpoints are
// configuration; the credentials come from OIDC_CLIENT_ID / OIDC_CLIENT_SECRET (environment or files in CIVI_MOUNT_DIR)
// and override the stored values, so they never end up in the database or in exported configuration.
$oidcClientId = $drupalSecret('OIDC_CLIENT_ID');
$oidcClientSecret = $drupalSecret('OIDC_CLIENT_SECRET');
if ($oidcClientId !== '' && $oidcClientSecret !== '') {
  $config['openid_connect.settings.generic']['settings']['client_id'] = $oidcClientId;
  $config['openid_connect.settings.generic']['settings']['client_secret'] = $oidcClientSecret;
}
