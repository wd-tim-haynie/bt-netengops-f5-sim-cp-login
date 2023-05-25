# F5 ClearPass Guest Login Simulation

The `f5-sim-cp-login` script is designed to simulate a guest login to ClearPass Guest with HTTPS, using F5 external monitor shell script and curl. This simulation can be a superior alternative to the standard https monitor proposed in the "Deploying CPPM with F5 BIG-IP Local Traffic Manager (LTM)" tech note, which hasn't been updated since 2014.

This script accesses the default login page of the guest application at `/guest/auth_login.php` and performs a guest operator login and logout. This test can identify potential failure points that the standard monitor may not detect, such as corruption of Web Login pages that would still pass a stock HTTPS monitor and even give a code 200.

## Installation and Update

To install or update the script on any F5 device:

1. Login to the F5 User Interface (UI).
2. Navigate to `System > File Management > External Monitor Program File List`.
3. Click `Import`.

To create a monitor object:

- On an LTM device, go to `Local Traffic > Monitors > Create`. Fill out the name and description, and select the external type.
- On a GTM (BigIP DNS) device, go to `DNS > GSLB > Monitors > Create`. Fill out the name and description, and select the external type.

After creating the monitor, add your USERNAME and PASSWORD. Initially, you can set these variables for a quick setup. Once the monitor is operational, it's recommended to use an encrypted password instead (see Password Encryption section).

## Script Variables

The script uses the following variables, which are set in the monitor object itself:

- `USERNAME`: your monitor username
- `PASSWORD`: plaintext password (should only be used for testing)
- `ENCRYPTED_PASSWORD`: an aes-256-cbc encrypted password (overrides `PASSWORD` if set)
- `DECRYPTION_KEY_FILE_NAME`: filename of the decryption key iFile for `ENCRYPTED_PASSWORD`
- `LOG_LEVEL`: (optional) logger level (debug, info, notice, warning, err, crit, alert, emerg)

There is no need to encode special characters with URL encoding (e.g., '%21' for '!') on the tested versions. However, this could be version-dependent. 

The script must be installed on all LTM pairs AND each GTM for accurate functioning. For GTM devices, you must manually install or update the script as these changes don't sync like other GTM configurations.

## Behavior and Error Detection

The script frequently uses "> /dev/null 2>&1". This is to ensure that the monitor only returns "UP" when the script completes fully. This is due to the behavior of the F5 external monitor, which considers the monitor successful if ANYTHING is output to STDOUT or STDERR.

The script checks for HTTP status code 302 intentionally, as an invalid username/password would return a status code 200 along with an error message, while a correct login would return a 302.

On the ClearPass side, configure your guest operator login policy to map the test username to the default "Null Profile". This allows login but assigns no privileges. The test username/password can be configured in the local user database, or an external resource like Active Directory if desired.

## Version History

- **1.3**: Simplified and improved logging, enhanced error handling, added password encryption, and fixed minor bugs.
- **1.2.1**: Moved MIN_LOG_LEVEL and LOGGING variables to be configured by the monitor. Enabled logging by setting LOGGING to true or specifying a valid MIN_LOG_LEVEL.
- **1.2**: Added password encryption and improved PID management, error detection, and cleanup.
- **1.1**: Initial published version with cleartext passwords and limited logging.

Please find details on password encryption and decryption in the subsequent sections.

## Password Decryption Key File

Only the first line of this file is read as the decryption key; all subsequent lines are disregarded. 

It's essential to upload this iFile to EVERY device - remember, GTMs don't automatically sync this information. If you have LTMs that are part of a sync group, they will synchronize this iFile among themselves.

## Password Encryption

1. Generate a secure, random 32-character (or longer) decryption key. Save this key in a text file temporarily.
2. Import this file into your LTMs and GTMs as an iFile via `System > File Management > iFile List`.
3. Run this command to encrypt your password: `echo 'your-password' | openssl enc -aes-256-cbc -base64 -k 'your-decryption-key'`
4. Save the encrypted password as a variable in the monitor with the name `ENCRYPTED_PASSWORD`.

## Limitations

1. When you upload a file as an iFile, the BIG-IP will append some numeric identifier, which isn't predictable. To avoid accidentally matching the wrong file, ensure you're using a unique file name for the decryption key file.
2. If you want to monitor the same resource in multiple locations (e.g., at the node and in the pool), create a separate monitor (with a different name) for each. Using the same monitor could unintentionally kill the process because the same pid file is used.

Please refer to the ClearPass F5 Tech Note here: https://www.arubanetworks.com/techdocs/ArubaDocPortal/content/cp-resources/cp-tech-notes.htm (Click the link for F5 Load Balancers)

The project has been tested on ClearPass 6.9.13 and BigIP 14.1.4.6.

## Disclaimer

Please use this script responsibly. It is intended for testing and troubleshooting purposes only, and should not be used for unauthorized access to any systems.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

## Authors

Tim Haynie, CWNE #254, ACMX #508 [LinkedIn Profile](https://www.linkedin.com/in/timhaynie/)
