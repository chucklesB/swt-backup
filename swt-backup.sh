#!/bin/bash

# swt-backup.sh - Use rsync to backup data to a network location

# Backup server settings
BACKUPSERVER="user@127.0.0.1"
REMOTEPATH="/media/backups"

# Styling
bold=$(tput bold)
normal=$(tput sgr0)

# Functions
main() {
    printBanner
    findWindowsPartitions
    promptPartitionSelection
    promptCustomerType
    promptCustomerName
    promptComputerName
    runBackup
}    

printBanner() {
    clear
    echo '
      ___________      _____________ __________                __                 
     /   _____/  \    /  \__    ___/ \______   \_____    ____ |  | ____ ________  
     \_____  \\   \/\/   / |    |     |    |  _/\__  \ _/ ___\|  |/ /  |  \____ \ 
     /        \\        /  |    |     |    |   \ / __ \\  \___|    <|  |  /  |_> >
    /_______  / \__/\  /   |____|     |______  /(____  /\___  >__|_ \____/|   __/ 
            \/       \/                      \/      \/     \/     \/     |__|    
    '
}

findWindowsPartitions() {
    # Find FAT/NTFS partitions
    echo -e "\nSearching for Windows partitions..."
    IFS=$'\n' PARTITIONS=( $(lsblk -pno KNAME,FSTYPE | grep 'ntfs' | awk '{print $1, "("$2")"}') )
    if [ ${#PARTITIONS[@]} -eq 0 ]; then
        read -p "No FAT/NTFS partitions found. Press enter to exit."
        exit 1
    fi

    # Find partitions containing important directories
    i=0
    for PARTITION in ${PARTITIONS[@]}; do
        # Create mountpoint
	PART=$(echo "${PARTITIONS[${i}]}" | awk '{print $1}')
	partname="$(basename ${PART})"
	mountpoint="/mnt/${partname}"
        if [ ! -d ${mountpoint} ]; then
            mkdir ${mountpoint}
            if [ $? -ne 0 ] || [ ! -d ${mountpoint} ]; then
                read -p "Error creating mountpoint ${mountpoint}. Press enter to exit."
                exit 1
            fi
        fi

	# Mount the partition
        sudo mount -o ro ${PART} ${mountpoint}
	if [ $? -ne 0 ]; then
            # Try ntfsfix before failing
            sudo ntfsfix ${PART}
            sudo mount -o ro ${PART} ${mountpoint}
            if [ $? -ne 0 ]; then
                read -p "Error mounting ${PART}. Press enter to exit."
                exit 1
            else
                # Look for Windows and Users directories
                if [ -d ${mountpoint}/Windows ]; then
                    echo -e "\n${PART}: Found Windows directory"
                    PARTITIONS[${i}]="${bold}${PARTITIONS[${i}]}${normal}"
                elif [ -d ${mountpoint}/Users ]; then
                    echo -e "\n${PART}: Found Users directory"
                    PARTITIONS[${i}]="${bold}${PARTITIONS[${i}]}${normal}"
                fi

                # Unmount partition
                sudo umount ${PART}
                if [ $? -ne 0 ]; then
                    read -p "Error unmounting ${PART}. Press enter to exit."
                    exit 1
                fi

                i=$((${i}+1))
	    fi
        else
            # Look for Windows and Users directories
            if [ -d ${mountpoint}/Windows ]; then
                echo -e "\n${PART}: Found Windows directory"
                PARTITIONS[${i}]="${bold}${PARTITIONS[${i}]}${normal}"
            elif [ -d ${mountpoint}/Users ]; then
                echo -e "\n${PART}: Found Users directory"
                PARTITIONS[${i}]="${bold}${PARTITIONS[${i}]}${normal}"
            fi

            # Unmount partition
            sudo umount ${PART}
            if [ $? -ne 0 ]; then
                read -p "Error unmounting ${PART}. Press enter to exit."
                exit 1
            fi

            i=$((${i}+1))
        fi
    done
}

promptPartitionSelection() {
    echo -e "\nSelect partitions to backup, one at a time. Select "Done" when finished. Partitions with Windows/Users folders are in ${bold}bold${normal}:"

    COLUMNS=1
    select PARTITION in "${PARTITIONS[@]}" "Done"; do
        if [ "${PARTITION}" = "Done" ]; then
            if [ ${#SELECTEDPARTS[@]} -eq 0 ]; then
                echo -e "\nNo partitions selected, try again:"
            else
                break
            fi
        elif [ -z "${PARTITION}" ]; then
            echo -e "\nInvalid option, try again:"
        else
            # Add device name to array if it doesn't already exist
            SELECTEDPART=$(echo "${PARTITION//${bold}/}" | awk '{print $1}')
            if [[ ! "${SELECTEDPARTS[*]}" =~ "${SELECTEDPART}" ]]; then
                SELECTEDPARTS+=( "${SELECTEDPART}" )
                echo -e "\nAdded ${SELECTEDPART}"
            else
                echo -e "\nDuplicate selection, try again:"
            fi
        fi

    done
}

promptCustomerType() {
    echo -e "\nChoose customer type:"
    OPTIONS=( "Individuals" "Internal" "Managed" "Unmanaged" )
    COLUMNS=1
    select opt in ${OPTIONS[@]}; do
        if [ -n "${opt}" ]; then
            customerType="$opt"
            break
        else
            echo -e "\nInvalid option, try again:"
        fi
    done
}

promptCustomerName() {
    while [ -z "${customerName}" ]; do
        echo -e "\nEnter customer name:"
        while read line; do
            if [ -z "${line}" ]; then
                echo -e "\nNo customer name entered, try again."
                break
            else
                customerName="${line}"
                break
            fi
        done < /dev/stdin
    done
}

promptComputerName() {
    while [ -z "${computerName}" ]; do
        echo -e "\nEnter computer name:"
        while read line; do
            if [ -z "${line}" ]; then
                echo -e "\nNo computer name entered, try again."
                break
            else
                computerName="${line}"
                break
            fi
        done < /dev/stdin
    done
}

runBackup() {
    BACKUPPATH="${customerType}/${customerName}/${computerName}"
    echo -e "\nSelected partition(s): ${SELECTEDPARTS[@]//${bold}/}"
    echo -e "\nBackup destination: ${BACKUPSERVER}:${REMOTEPATH}/${BACKUPPATH}"
    while true; do
        read -p "Are you sure you want to continue? " yn
        case $yn in
            [Yy]* ) \
                for part in ${SELECTEDPARTS[@]//${bold}/}; do
                    # Create mountpoint
		    partname="$(basename ${part})"
		    mountpoint="/mnt/${partname}"
                    if [ ! -d ${mountpoint} ]; then
                        mkdir ${mountpoint}
                        if [ $? -ne 0 ] || [ ! -d ${mountpoint} ]; then
                            read -p "Error creating mountpoint ${mountpoint}. Press enter to exit."
                            exit 1
                        fi
                    fi

                    # Mount the partition
                    sudo mount -o ro ${part} ${mountpoint}
                    if [ $? -ne 0 ]; then
                        read -p "Error mounting ${part}. Press enter to exit."
                        exit 1
                    fi

                    # Run the backup
		    rsync -rltv --mkpath --exclude Windows --exclude WINDOWS --exclude '*.sys' --exclude '*.SYS' "${mountpoint}/" ${BACKUPSERVER}:"${REMOTEPATH}/${BACKUPPATH// /\\ }/${partname}"
                    if [ $? -ne 0 ]; then
			sudo umount ${part}
                        if [ $? -ne 0 ]; then
                            read -p "Error unmounting ${part}. Press enter to exit."
                            exit 1
                        fi
                        read -p "Backup failed. Press enter to exit."
                        exit 1
                    fi

                    # Unmount the partition
                    sudo umount ${part}
                    if [ $? -ne 0 ]; then
                        read -p "Error unmounting ${part}. Press enter to exit."
                        exit 1
                    fi
                done
            break;;

            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

    echo -e "\nFinished! Be sure to verify the backup!"
}

main "$@"; exit
