#!/bin/zsh --no-rcs

IFS=$'\n'
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

mspName=""
mspContactNumber=""
iconURL=""

# If testingMode is set to 1, the script will not check for the condition file, and always run.
testingMode=0

conditionFile="/Library/Application Support/${mspName}/setupDone.json"

# Progress 1st with swiftDialog (auto installation at enrollment)
instance="e" # Name of used instance

mspDir="/Library/Application Support/${mspName}"
mspIcon="${mspDir}/images/$(basename "${iconURL}")"

apps=(
    "Xcode Command Line Tools,/usr/bin/xcodebuild"
    "Installomator,/usr/local/Installomator/Installomator.sh"
    "swiftDialog,/usr/local/bin/dialog"
    "azcopy,/usr/local/bin/azcopy"
    "PlistBuddy,/usr/libexec/PlistBuddy"
    "desktoppr,/usr/local/bin/desktoppr"
    "dockutil,/usr/local/bin/dockutil"
    "diskspace,/usr/local/bin/diskspace"
)

# Dialog display settings, change as desired
title="Deploying ${mspName} CLT"
message="Please wait while essential ${mspName} tools are deployed..."
endMessage="Installation complete! Please restart your Mac to continue"
displayEndMessageDialog=1 # Should endMessage be shown as a dialog? (0|1)
errorMessage="A problem was encountered setting up this Mac.<br>Please contact ${mspName} on ${mspContactNumber}"

######################################################################
# Progress 1st Dialog
#
# Showing installation progress using swiftDialog
# No customization below…
######################################################################
# Complete script meant for running via MDM on device enrollment. This will download
# and install Dialog on the fly before opening Dialog.
#
# Log: /private/var/log/InstallationProgress.log
# This file prevents script from running again on Addigy and Microsoft Endpoint (Intune):
# "/var/db/.Progress1stDone"
#
# Display a Dialog with a list of applications and indicate when they’ve been installed
# Useful when apps are deployed at random, perhaps without local logging.
# Applies to Mosyle App Catalog installs, VPP app installs, Installomator installs etc.
# The script watches the existence of files in the file system, so that is used to show progress.
#
# Requires Dialog v2 or later (will be installed) https://github.com/swiftDialog/swiftDialog
#
# NOTE about MDM solutions:
# This script might not be usefull for the following solutions as they
# have their own solution for deployment progress:
# - mosyleb,mosylem  Mosyle has Embark
# - kandji           Kandji has LiftOff
#
######################################################################
#
#  This script made by Søren Theilgaard and Tully Jagoe
#  https://github.com/Theile
#  https://github.com/tully-systima
#  Twitter and MacAdmins Slack: @theilgaard
#
#  Based on the work by Adam Codega:
#  https://github.com/acodega/dialog-scripts
#
#  Some functions and code from Installomator:
#  https://github.com/Installomator/Installomator
#
######################################################################
# List of apps/installs to process in “apps” array.
# Provide the display name as you prefer and the path to the app/file. ex:
#       "Google Chrome,/Applications/Google Chrome.app"
# A comma separates the display name from the path. Do not use commas in your display name text.
#
# Tip: Check for something like print drivers using the pkg receipt, like:
#       "Konica-Minolta drivers,/var/db/receipts/jp.konicaminolta.print.package.C759.plist"
#      Or fonts, like:
#       "Apple SF Pro Font,/Library/Fonts/SF-Pro.ttf"
######################################################################
scriptVersion="10.0"
# v. 10.0   : 2025-06-18 : More options for MSP configuration and improved variable handling. Improved conditionFile and added post setup reboot. ~ @tully-systima
# v.  9.8   : 2023-10-06 : Support for FileWave, and previously Kandji. Update Progress 1st swiftDialog.sh to use native checkmark #1220
# v.  9.7   : 2022-12-19 : Fix for LOGO_PATH for ws1
# v.  9.6   : 2022-11-15 : GitHub API call is first, only try alternative if that fails.
# v.  9.5   : 2022-09-21 : change of GitHub download
# v.  9.4   : 2022-09-14 : downloadURL can fall back on GitHub API
# v.  9.3   : 2022-08-29 : Logging changed for current version. Improved installation with looping if it fails, so it can try again. Improved GitHub handling.
# v.  9.2.2 : 2022-06-17 : Improved Dialog installation. Check 1.1.1.1 for internet connection.
# v.  9.2   : 2022-05-19 : Not using GitHub api for download of Dialog, show a dialog when finished to make message more important. Now universal script for all supported MDMs based on LOGO variable.
# v.  9.0   : 2022-05-16 : Based on acodega’s work, I have added progress bar, changed logging and use another log-location, a bit more error handling for Dialog download, added some "|| true"-endings to some lines to not make them fail in Addigy, and some more.
######################################################################

# ================================================================================
# MARK: Check blocking file
[[ "${testingMode}" -eq 0 ]] && {
    [[ -f "${conditionFile}" ]] && {
        echo "1st Setup is already completed, exiting..."
        exit 0
    }
}

# No sleeping
/usr/bin/caffeinate -d -i -m -u &
caffeinatepid=$!
caffexit () {
    kill "$caffeinatepid" || true
    printlog "[LOG-END] Status $1"
    exit $1
}

# MARK: Functions
installomatorLog="/private/var/log/Installomator.log"
function printlog(){
    timestamp=$(date +%F\ %T)
    [[ "$(stat -f%Su /dev/console)" == "root" ]] && echo "${timestamp} :: ${label} : ${1}" | tee -a "${installomatorLog}" || echo "${timestamp} :: ${label} : ${1}"
}
printlog "[LOG-BEGIN] ${logMessage}"

# Internet check
[[ "$(nc -z -v -G 10 1.1.1.1 53 2>&1 | grep -io "succeeded")" != "succeeded" ]] && {
    printlog "ERROR. No internet connection, we cannot continue."
    exit 90
}

# Get the MSP Icon
[[ ! -d "${mspDir}/images" ]] && {
    sudo mkdir -p "${mspDir}/images"
    sudo curl -fsSL "${iconURL}" -o "${mspDir}/images/$(basename "${iconURL}")"
    sudo chown root:wheel "${mspDir}"
    sudo chmod 755 "${mspDir}"
    sudo chmod 700 "${mspDir}/images"
}

# MARK: MDM Agents
[[ $(profiles -C -v | grep -c "mosyle") -gt 0 ]] && {
    printlog "Mosyle MDM detected, adding Self-Service"
    apps+=(
        "Self Service,/Applications/Self-Service.app"
    )
}
[[ $(profiles -C -v | grep -c "jumpcloud") -gt 0 ]] && {
    printlog "Jumpcloud MDM detected, adding Jumpcloud Agent"
    apps+=(
        "Jumpcloud,/Applications/Jumpcloud.app"
    )
}

# MARK: Parse variables
logMessage="${instance}: Progress 1st with Dialog, v${scriptVersion}"
label="P1st-v${scriptVersion}"

# Location of dialog and dialog command file
dialogApp="/usr/local/bin/dialog"
dialogCommandFile="/var/tmp/dialog.log"
progressCounterFile="/var/tmp/Progress1st.plist"

# Counters
progressIndex=0
stepProgress=0
defaults write ${progressCounterFile} step -int 0
progressTotal=${#apps[@]}
printlog "Total watched installations: ${progressTotal}"
printlog "mspIcon: ${mspIcon}"

# Wait for sign in
waitForUser(){
    # From @acodega
    setupAssistantProcess=$(pgrep -l "Setup Assistant")
    until [[ "${setupAssistantProcess}" = "" ]]; do
        printlog "Setup Assistant Still Running. PID ${setupAssistantProcess}"
        sleep 1
        setupAssistantProcess=$(pgrep -l "Setup Assistant")
    done
    printlog "Out of Setup Assistant"
    printlog "Logged in user is $(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')"

    finderProcess=$(pgrep -l "Finder")
    until [[ "${finderProcess}" != "" ]]; do
    printlog "Finder process not found. Assuming device is at login screen. PID ${finderProcess}"
        sleep 1
        finderProcess=$(pgrep -l "Finder")
    done
    printlog "Finder is running"
    printlog "Logged in user is $(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')"

    # Get the current logged in user
    username=$(stat -f "%Su" /dev/console)
    uid=$(id -u "${username}")
    printlog "Logged in user is ${username} with ID ${uid}"
}

# execute a dialog command
echo "" > "${dialogCommandFile}" || true
function dialog_command(){
    printlog "Dialog-command: ${1}"
    echo "${1}" >> "${dialogCommandFile}" || true
}

# MARK: Install Dialog
installDialog() {
    printlog "Installing Dialog..."
    # Embed the MSP icon into the Dialog app
    [[ -f "/Library/Application Support/Dialog/Dialog.png" ]] && {
        printlog "Pre-embedding MSP icon into Dialog..."
        sudo mkdir -p "/Library/Application Support/Dialog"
        sudo cp "${mspIcon}" "/Library/Application Support/Dialog/Dialog.png"
    }

    # Get latest Dialog download URL from GitHub API
    printlog "Getting latest Dialog release from GitHub..."
    dialogInstallURL=$(curl -sfL "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' '/"browser_download_url":/ { print $4 }' | head -1)

    printlog "Dialog download URL: ${dialogInstallURL}"

    # Download Dialog installer
    dialogPKG="/tmp/install_swiftDialog.pkg"
    printlog "Downloading Dialog installer..."
    sudo curl -fsSL "${dialogInstallURL}" -o "${dialogPKG}"

    [[ ! -f "${dialogPKG}" ]] && {
        printlog "ERROR: Failed to download Dialog installer"
        exit 91
    }

    # Install Dialog
    printlog "Installing Dialog..."
    sudo installer -pkg "${dialogPKG}" -target /

    # Verify installation
    [[ ! -x "${dialogApp}" ]] && {
        printlog "ERROR: Dialog installation failed"
        exit 92
    }

    printlog "Dialog installed successfully"

    # Clean up
    rm -f "${dialogPKG}"
}

function appCheck(){
    dialog_command "listitem: $(echo "${app}" | cut -d ',' -f1): wait"
    while [[ ! -e "$(echo "${app}" | cut -d ',' -f2)" ]]; do
        sleep 2
    done
    dialog_command "progresstext: Install of “$(echo "${app}" | cut -d ',' -f1)” complete"
    dialog_command "listitem: $(echo "${app}" | cut -d ',' -f1): success"
    progressIndex=$(defaults read "${progressCounterFile}" step)
    progressIndex=$(( progressIndex + 1 ))
    defaults write "${progressCounterFile}" step -int "${progressIndex}"
    dialog_command "progress: ${progressIndex}"
    printlog "at item number ${progressIndex}"
}

# Install Dialog
[[ ! -e "${dialogApp}" ]] && {
    installDialog
} || {
    printlog "Dialog already installed"
}

# MARK Run Dialog
dialogCMD="\"${dialogApp}\" --title \"${title}\" \
--message \"${message}\" \
--icon \"${mspIcon}\" \
--progress ${progressTotal} \
--button1text \"Please Wait\" \
--button1disabled \
--button2text \"Cancel\" \
--button2disabled \
--blurscreen \
--ontop"

# Create the list of apps
listitems=""
for app in "${apps[@]}"; do
  listitems="${listitems} --listitem '$(echo "${app}" | cut -d ',' -f1)'"
done

# Final command to execute
dialogCMD="${dialogCMD} ${listitems}"
printlog "${dialogCMD}"

# Wait for user login to complete
waitForUser

# Launch dialog and run it in the background sleep for a second to let thing initialise
printlog "Starting Dialog as ${username}"
launchctl asuser "${uid}" sudo -iu "${username}" bash -c "${dialogCMD}" &
sleep 2

(for app in "${apps[@]}"; do
    #stepProgress=$(( 1 + progressIndex ))
    #dialog_command "progress: $stepProgress"
    sleep 0.5
    appCheck &
done

wait)

# ================================================================================
# MARK: Finishing

# Prevent re-run of script if conditionFile is set
[[ ! -f "${conditionFile}" ]] && {
    echo "{}" > "${conditionFile}" || true
}
printlog "Marking script as completed"
echo "{}" > "${conditionFile}" || true
jq --arg date "$(date +%d/%m/%y)" '. + {"1stSetupDone": $date}' "${conditionFile}" > "${conditionFile}.tmp" && sudo mv "${conditionFile}.tmp" "${conditionFile}"
rm -f "${conditionFile}.tmp"

dialog_command "progress: complete"
dialog_command "progresstext: Deployment complete!"
echo -e "[SUCCESS]: 1st Setup is complete"
sleep 3

# Display the end message and restart countdown
printlog "Finalizing."

# MARK: Restart countdown
# 60 second countdown with restart functionality
dialog_command "button1: enable"
dialog_command "button2: enable"
dialog_command "button1text: Restart Now"
dialog_command "button2text: Cancel Restart"
dialog_command "progress: complete"
dialog_command "activate:"
countdown=60
restart=true
while [[ "${countdown}" -gt 0 && "${restart}" = true ]]; do
    case $? in
        0)
            printlog "Restart button pressed"
            restart=true
            ;;
        2)
            printlog "Cancel restart button pressed"
            restart=false
            ;;
        *)
            printlog "Timer expired, proceeding with restart"
            restart=true
            ;;
    esac
    echo "progresstext: Device will restart in ${countdown} seconds" > "${dialogCommandFile}"
    # Check for user interaction
    sleep 1
    ((countdown--))
done

# Close dialog and restart
dialog_command "quit:"
printlog $(rm -fv "${dialogCommandFile}" || true)
printlog $(rm -fv "${progressCounterFile}" || true)

printlog "Ending"
[[ "${testingMode}" -eq 0 ]] && {
    [[ "${restart}" = true ]] && {
    printlog "Restarting device..."
        sudo shutdown -r now
    }
}
