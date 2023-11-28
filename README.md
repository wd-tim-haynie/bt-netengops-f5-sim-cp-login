# F5 ClearPass Guest Login Simulation

The `f5-sim-cp-login` script serves as an F5 external monitor, specifically designed to simulate login and logout of the ClearPass Guest application's default login page located at `/guest/auth_login.php`. This simulation offers a more reliable alternative to the standard HTTPS monitor proposed in the "Deploying CPPM with F5 BIG-IP Local Traffic Manager (LTM)" guide, which hasn't been updated since 2014. By employing this script, you gain a robust method to monitor the status of the ClearPass Guest application, surpassing the capabilities of the BIG-IP's built-in HTTP/HTTPS monitor.

Notably, it enables the detection of potential issues such as corrupted Web Login pages, which would otherwise pass the stock HTTP/HTTPS healthcheck monitor and even return an HTTP status code of 200 despite having a blank body. This can happen if the ClearPass Guest database somehow gets corrupt. Moreover, the script can also load and verify the status of any additional pages that you wish to monitor. This feature enhances the monitoring capabilities, ensuring not just the functionality of the login page, but also the accessibility and health of other critical pages in your application. 

## Installation and Update

Follow these steps to install or update the script on an F5 device:

1. Login to the F5 User Interface (UI).
2. Navigate to `System > File Management > External Monitor Program File List > Import`.
3. Click the `Browse` button and select the script file.
4. Select either `Create New` or `Overwrite Existing`.
5. Type a name for the script in the `Name` field, for example: `sim_cp_login.sh`.
6. Click `Import` to complete.

To create a monitor object:

- On an LTM device, go to Local Traffic > Monitors > Create. Fill in the name and description fields, and select 'External' as the type.
- On a GTM (BigIP DNS) device, go to DNS > GSLB > Monitors > Create. Fill in the name and description fields, and select 'External' as the type.

Consider including a link to this GitHub repository in the description field of the monitor to facilitate future references and updates, especially since the operational details of this script aren't documented elsewhere.

Then, add `USERNAME` and `PASSWORD` variables. In the Variables section of the monitor configuration, set `USERNAME` to your test username and click 'Add'. Then set `PASSWORD` to your test password and click 'Add' again. For a quick setup, you can initially use the plaintext `PASSWORD` variable. However, it's recommended to switch to an encrypted password once the monitor is operational (refer to the Password Encryption section).

Finally, click 'Finished' to complete the configuration of your monitor object.

The script must be installed on all LTM pairs AND each GTM for accurate functioning. For GTM devices, you must manually install or update the script as these changes don't sync like other GTM configurations.

On the ClearPass side, configure your guest operator login policy to map the test username to the default "Null Profile". This allows login but assigns no privileges. The test username/password can be configured in the local user database, or an external resource like Active Directory if desired.

## Script Variables

The script uses the following variables, which are set in the monitor object itself:

- `USERNAME`: your monitor username
- `PASSWORD`: plaintext password (should only be used for testing)
- `ENCRYPTED_PASSWORD`: an aes-256-cbc encrypted password (overrides `PASSWORD` if set)
- `DECRYPTION_KEY_FILE_NAME`: filename of the decryption key iFile for `ENCRYPTED_PASSWORD`
- `LOG_LEVEL`: (optional) logger level (debug, info, notice, warning, err, crit, alert, emerg)

There is no need to encode special characters with URL encoding (e.g., '%21' for '!') on the tested versions. However, this could be version-dependent. 

## Script Arguments

If you wish to monitor other pages on the ClearPass appliance, you can add their URIs as arguments in the monitor. For instance, you could effectively monitor the ClearPass admin server service (cpass-admin-server) by adding `/tips/welcome.action` as an argument.

It's also best practice to monitor any critical pages involved in your captive portal login process. For monitoring captive portal pages in the ClearPass Guest application, append the URI with `?_browser=1`. This query parameter simulates the behavior of a real browser. Failing to include it may result in a different status code than expected.

For example, you could add `/tips/welcome.action /guest/mycaptiveportallanding.php?_browser=1` as arguments to the script, which will then monitor these two pages.

## Behavior and Error Detection

The script frequently uses "> /dev/null 2>&1". This is to ensure that the monitor only returns "UP" when the script completes fully. This is due to the behavior of the F5 external monitor, which considers the monitor successful if ANYTHING is output to STDOUT.

The script is designed to intentionally check for an HTTP status code 302. This is because an incorrect login attempt will still return a status code 200 with an error message will be embedded within the HTML body. Conversely, a successful login will generate a 302 status code, signifying appropriate redirection after the authentication process.

## Password Encryption

1. Begin by generating a secure, random decryption key with at least 32 characters. Temporarily save this key in a text file.
2. Import the text file containing your decryption key into your LTMs and GTMs using the `System > File Management > iFile List` function.
3. Use the following command to encrypt your password: `echo 'your-password' | openssl enc -aes-256-cbc -base64 -k 'your-decryption-key'`.
4. Within your monitor, define a variable named `DECRYPTION_KEY_FILE_NAME` and assign the name of the iFile as its value. It's important to choose a highly unique file name, as discussed in the **Limitations** section of this document.
5. Similarly, in the monitor, define another variable called `ENCRYPTED_PASSWORD` and assign the output from Step 3 as its value.
6. After you've made these changes to the monitor, remember to save your updates to the monitor using the "Finished" or "Update" button.
7. Ensure you delete the key file from any non-F5 systems once you've completed these steps.

### Password Decryption Key File

Only the first line of this file is read as the decryption key; all subsequent lines are disregarded. 

It's essential to upload this iFile to EVERY device - remember, GTMs don't automatically sync this information. If you have LTMs that are part of a sync group, they will synchronize this iFile among themselves.

## Limitations

1. When you upload a file as an iFile, the BIG-IP will append some numeric identifier, which isn't predictable. To avoid accidentally matching the wrong file, ensure you're using a unique file name for the decryption key file.
2. If you want to monitor the same resource in multiple locations (e.g., in two different pools), create a separate monitor (with a unique name) for each location. Using the same monitor for the same resource in different locations could unintentionally cause the scripts to interfere with each other due to the shared usage of the same process ID (pid) file.

## Post Deployment Monitoring

It is critical to understand that this is a resource intensive monitor on ClearPass. By default, it involves 2 GETs and 1 POST, and each additional URI monitored is an additional GET. Additionally, the BIG-IP architecture is such that monitors are run independantly on each BIG-IP, rather that from just the active LTM, which in effect incrementally multiplies the monitoring interval for each F5 that is running this monitor. ClearPass has a limited number of threads and resources that it can allocate to HTTP. Therefore, it is critical make sure that you are not overloading your ClearPass infrastructure when you utilize this monitor.

Consequences of an overloaded ClearPass can be as mild as the subscriber coming out of sync or as severe as the replication service on the publisher being impacted by an overwhelmed subscriber. In the latter scenario, a single problematic subscriber can cause the publisher replication service to crash. When that happens, the entire cluster to fall out of sync until it auto-recovers, which could take 15 minutes or more until everything comes back into sync. Meanwhile, new guest devices cannot registerand new Onboard users cannot onboard, as well as any other consequence that could potentially arise from an out of sync infrastructure.

When deploying this script, monitor the following conditions:
* User CPU on each node (should not be pegged)
* Sync status of each node (should not fall out of sync regularly)
* Status of the DB replication service (aka cpass-replication service on CLI) on the publisher (should not be stopped)

If you find a particular node to be particularly problematic with sync issues or CPU after deploying this script, you need to tune down the monitor interval on the LTM. Sometimes, rebooting the affected node might be required.

If the DB replication service is stopped on the publisher or any other node, it will eventually auto-restart, or you can restart it immediately at the CLI with `service restart cpass-replication`. Note that `restart` should be used instead of `start`.

## Troubleshooting

In case you encounter issues while running the script, refer to the following troubleshooting steps:

1. **Check Login Credentials:** Ensure your username and password can successfully log into `/guest/auth_login.php` from a web browser. Use the Access Tracker in ClearPass to confirm a successful login status.
2. **Open Log:** Log into the F5 bash shell and execute the command `tail -f /var/log/ltm`. Keep this window open while troubleshooting.
3. **Set Debug Level:** In the monitor configuration, set the `LOG_LEVEL` variable to `debug`.
4. **Configure Password:** Remove the `ENCRYPTED_PASSWORD` variable and set the `PASSWORD` variable to your plaintext password.
5. **Check Log for Errors:** With the log still open, verify if the script functions as expected with the plaintext password. Any errors or issues will be logged here.
6. **Verify ClearPass Access Tracker:** Check the ClearPass Access Tracker to confirm if it's receiving the request from the test username and verify its response.
7. **Test Encrypted Password:** Once the script functions correctly with the plaintext password, retry with the encrypted password. Ensure `DECRYPTION_KEY_FILE_NAME` is correctly set to the appropriate file. If necessary, uncomment the following lines in your script for additional debugging:
        `#LOG_MESSAGE "Decryption Key: $DECRYPTION_KEY" "debug"`
        `#LOG_MESSAGE "Decrypted Password: $PASSWORD" "debug"`
   Remember that this could potentially expose sensitive information in your logs, especially if they're transmitted in cleartext to a syslog server. To avoid this risk, consider redirecting these messages to a separate output file by uncommenting these lines and replacing `/path/to/outputfile` with a valid path:
        `#echo "Decryption Key: $DECRYPTION_KEY" >> /path/to/outputfile`
        `#echo "Decrypted Password: $PASSWORD" >> /path/to/outputfile`
   Ensure to securely delete this output file once you're done with debugging and to comment out the two log messages above.
8. **Unset Debug Level:** Once everything functions as expected, delete the `LOG_LEVEL` variable to stop the verbose logging and return it to the default level. Also, remember to re-comment any lines that were uncommented during the debugging process in step 7 to maintain the security of your environment and prevent potentially sensitive information from being logged.

## About

Please refer to the ClearPass F5 Tech Note here: https://www.arubanetworks.com/techdocs/ArubaDocPortal/content/cp-resources/cp-tech-notes.htm (Click the link for F5 Load Balancers)

The project has been tested on:
* ClearPass 6.9.13
* BigIP 14.1.4.6
* BigIP 14.1.5.4

### Version History

- **1.5**: Minor efficiency improvements, no new features. 
- **1.4**: Added the capability to monitor any page, using arguments passed from the monitor.
- **1.3**: Simplified and improved logging, enhanced error handling, added the ability to specify any decryption key file, and fixed minor bugs. Deprecated `MIN_LOG_LEVEL` and `LOGGING` variables, replaced with `LOG_LEVEL`
- **1.2.1**: Moved `MIN_LOG_LEVEL` and `LOGGING` variables to be configured by the monitor. Enabled logging by setting `LOGGING` to true or specifying a valid `MIN_LOG_LEVEL`.
- **1.2**: Added password encryption and improved PID management, error detection, and cleanup.
- **1.1**: Initial published version with cleartext passwords and limited logging.

### Disclaimer

This script is provided for the purpose of testing and troubleshooting, and is intended to be used in a responsible manner. It is not designed for, and should not be used for, unauthorized access to any systems. While efforts have been made to ensure its accuracy and reliability, the author assumes no responsibility for any issues or complications that may arise from the use of this script within your environment. Users are advised to carefully evaluate the script's applicability to their specific needs and to take appropriate precautions in its usage.

### License

This project is licensed under the MIT License. See the LICENSE file for more details.

### Author

Tim Haynie, CWNE #254, ACMX #508 [LinkedIn Profile](https://www.linkedin.com/in/timhaynie/)
