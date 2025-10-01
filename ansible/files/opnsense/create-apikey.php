#!/usr/local/bin/php
<?php
/*
 * PrivateBox - OPNsense API Key Generator
 *
 * Generates a new API key for the root user using OPNsense internal libraries.
 * Returns JSON with key and secret for automation purposes.
 *
 * Usage: php create-apikey.php
 * Output: {"result":"ok","key":"...","secret":"..."}
 */

require_once('script/load_phalcon.php');
require_once('legacy_bindings.inc');

use OPNsense\Core\Config;
use OPNsense\Auth\User;

try {
    Config::getInstance()->lock();

    $userModel = new User();
    $user = $userModel->getUserByName("root");

    if ($user === null) {
        echo json_encode([
            "result" => "failed",
            "error" => "Root user not found"
        ]);
        Config::getInstance()->unlock();
        exit(1);
    }

    // Generate new API key
    $apikey = $user->apikeys->add();

    if (empty($apikey)) {
        echo json_encode([
            "result" => "failed",
            "error" => "Failed to generate API key"
        ]);
        Config::getInstance()->unlock();
        exit(1);
    }

    // Save configuration
    $userModel->serializeToConfig(false, true);
    Config::getInstance()->save();

    // Return key and secret
    echo json_encode([
        "result" => "ok",
        "key" => $apikey["key"],
        "secret" => $apikey["secret"]
    ]);

    exit(0);

} catch (Exception $e) {
    echo json_encode([
        "result" => "failed",
        "error" => $e->getMessage()
    ]);
    Config::getInstance()->unlock();
    exit(1);
}
?>
