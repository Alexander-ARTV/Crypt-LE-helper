# Crypt-LE-helper
A few auxiliary tools to help automate [Crypt-LE](https://github.com/do-know/Crypt-LE) certificate requests using DNS-verification with a two-pass method. This allows for creating your own method of supplying the challenge token(s) to your DNS provider before running Crypt LE a second time for verification.


## These are the included files and their functions
- Dockerfile - Let's you build a custom image based on [my modified version of Crypt-LE](https://github.com/Alexander-ARTV/Crypt-LE/tree/resume),
hopefully this will become obsolete soon when the functionality finds it's way into the original package.
- compose.yaml - This compose-file creates the Crypt-LE container, edit this with the appropriate image name after building the image
- generate_certs.ps1 - The main useful piece of software, this script handles everything from setting up a folder structure for the compose file, running Crypt-LE, performing DNS token registration, and it contains a simple way to distribute the created certificates using SSH/SCP
- log.conf - Used by the script to setup logging to a file
- targets_example.txt - Example file with syntax explanation for the automatic distribution functionality.

### generate_certs.ps1
This file can be used interactively or non-interactively to handle the entire certificate generation and distribution process for a small site using DNS-verification. In it's current form, it is hard coded to push challenge tokens to Cloudflare via it's API. However, these functions (Write-CloudflareIDs and ClearCloudflareIDs) can be easily modified to suit other needs.

The file takes a few parameters to allow for unnatended distribution using a cron job, or just for convenience when running the script manually. However, it is recommended to run the script manually the first time to test functionality and perform inital setup:

- Domain (string)
- Renew (number) - Number of days to allow for renewal, defaults to 0
- Unattended (switch) - Disables any request for user input, checks that all requirements to run are fulfilled and makes some well balanced decisions
- KeepChallenges (switch) - In case you want to keep the challenge files created in the filesystem by Crypt-LE (./data/challenges) and the DNS TXT entries for manual inspection and deletion
- AutoDistribute (switch) - Enables the automatic distribution feature available - make sure to setup and share SSH identities to the machine hosting the script to use this feature unattended, there is currently no graceful handling of for example passwort prompts

The script has been tested with Powershell 7.x under Ubuntu.


### targets_example.txt
A file used for automatic distribution to devices.

Lines starting with @ denotes file types to transfer, file endings will be appended to the current certificate name by the script to specify which files to transfer.
Lines containing a connection string will be used as a target for the files constructed from the last preceding file type specification.
Lines starting with & are commands that will be run, typically to further load the certificates on targets or reload specific services.
Make sure to setup and share SSH identities to the machine hosting the script to be able to use unattended distribution.
