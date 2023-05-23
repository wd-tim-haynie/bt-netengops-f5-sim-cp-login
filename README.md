# wd-f5-sim-cp-login
Simulates login to ClearPass Guest with HTTPS from F5 external monitor shell script using curl

The script loads the system default login page for the guest application, /guest/auth_login.php and performs a guest operator login and logout. This is a significantly better test that the stock https monitor that is recommended in the "Deploying CPPM with F5 BIG-IP Local Traffic Manager (LTM)" tech note, which hasn't been updated since 2014. The stock monitor is pretty good, but wouldn't be able to capture as many failure use cases. I've run into an instance in my environment where a single ClearPass node had corrupt versions of the Web Login pages, so the stock monitor was passing just fine even though it was actually broken. Even checking for a Receive String of 200 did not catch the problem as the page was still responding with this code.

To install/update the script on any F5, login to the UI and go to System > File Management > External Monitor Program File List and click Import.

Now create a monitor object. On an LTM device, create an external monitor Local Traffic > Monitors > Create > provide, name description, and choose type external. On a GTM (BigIP DNS) device, go to DNS > GSLB > Monitors > Create > provide, name description, and choose type external.

For current version of the script, the username and password must be specified in the monitor with the variables USERNAME and PASSWORD (Name = USERNAME, Value = the test username, click Add, then Name = PASSWORD, Value = your test password, and click Add). On my tested versions, there is no need to encode special characters with URL encoding (for example '%21' for an exclamation mark '!' or '%40' for an at sign '@', etc.) but that could depend on your version of curl. Both were tested on my versions and both seem to work fine.

Also make sure that you are not using a sensitive username and password since this is being stored in cleartext in your configuration, display unobscured onscreen, and will be visible to F5 if you submit a qkview. My username and password are stored in the local user repository on ClearPass and it is only used for this specific purpose. You could choose to modify the script to store the username and password as an environment variable in your bash profile to make it slightly more hidden but I think this might still be visible to F5 in the qkview. I'm not aware of any way to encrypt the password nicely yet but I'll keep looking.

The script must be installed on all LTM pairs AND each GTM to work correctly. You can deploy/update the script on a single LTM in the pair and then sync to force the script to copy over to the other member. However, *you must manually install/update the script on each GTM* as this information does not sync like the rest of the GTM configurations.

I have my environment set to 10 second interval, 31 second timeout. On GTM, 9 second probe timeout.

Note the usage of "> /dev/null 2>&1" regularly in the script. This is included due to the behavior of F5 external monitor. If ANYTHING is output to STDOUT or STDERR, the monitor is considered successful and the resource is considered available. Therefore it is critical to include this on any command that could potentially output something to prevent that from happening. We only want the output "UP" to occur if the script gets to the very end.

Also note that I am checking for HTTP status code 302, this is also very intentional. In my testing I found that an invalid username and password would simply reload the page with an error message displayed, with a status code 200. When a correct username and password were specified, a 302 was returned.

On the ClearPass side, configure your guest operator login policy such that the test username is mapped to the default "Null Profile" (can log in but has no privileges) operator login in ClearPass Guest.

Tested on ClearPass 6.9.13 and BigIP 14.1.4.6.

The ClearPass F5 Tech Note can be found here: https://www.arubanetworks.com/techdocs/ArubaDocPortal/content/cp-resources/cp-tech-notes.htm (Click the link for F5 Load Balancers)
