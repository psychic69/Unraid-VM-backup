#!/bin/bash

#
# Main function to determine VM backup sources based on libvirt XML data.
#
vm_source_backup() {
    # --- Configuration ---
    # Set to "Y" to only back up the primary boot disk.
    # Set to anything else to back up all .img disks, sorted by boot order.
    local VM_BACKUP_PRI_ONLY="N"
    local VM_LIST="vm_list.ini"

    # --- Pre-flight Checks ---
    if ! command -v virsh &> /dev/null; then
        echo "Error: 'virsh' command not found. Please ensure libvirt client is installed." >&2
        return 1
    fi

    if [[ ! -f "$VM_LIST" ]]; then
        echo "Error: VM list file not found at '$VM_LIST'" >&2
        return 1
    fi

    # --- Initialization ---
    # Declare the array to hold the final results.
    declare -a vm_backup_array

    # --- Main Logic ---
    # Read the VM list file line by line.
    while IFS= read -r vm_name || [[ -n "$vm_name" ]]; do
        # Skip empty lines or lines that start with a '#' comment.
        [[ -z "$vm_name" || "$vm_name" =~ ^# ]] && continue

        echo "INFO: Processing VM: $vm_name" >&2

        # Get the VM's XML configuration. Use --inactive to get info even if VM is off.
        local virsh_xml
        if ! virsh_xml=$(virsh dumpxml "$vm_name" --inactive 2>/dev/null); then
            echo "WARN: Could not get XML for VM '$vm_name'. It may not exist. Skipping." >&2
            continue
        fi

        # Use awk to parse XML and create tuples of (boot_order, file_path)
        local image_tuples
        image_tuples=$(echo "$virsh_xml" | awk '
            BEGIN { RS="</disk>" }
            /type='\''file'\''/ && /device='\''disk'\''/ {
                boot_order = 99
                if (match($0, /<boot order='\''([0-9]+)'\''\/>/, b)) {
                    boot_order = b[1]
                }
                if (match($0, /<source file='\''([^'\'']+\.img)'\''/, s)) {
                    print boot_order, s[1]
                }
            }
        ')
        
        # Continue if no suitable disks were found.
        if [[ -z "$image_tuples" ]]; then
            echo "WARN: No suitable '*.img' disk files found for VM '$vm_name'." >&2
            continue
        fi

        # Get the sorted list of full paths, one per line.
        local sorted_full_paths
        sorted_full_paths=$(echo "$image_tuples" | sort -n | cut -d' ' -f2-)

        # Determine which paths to process based on VM_BACKUP_PRI_ONLY
        local paths_to_process
        if [[ "$VM_BACKUP_PRI_ONLY" == "Y" ]]; then
            paths_to_process=$(echo "$sorted_full_paths" | head -n 1)
        else
            paths_to_process="$sorted_full_paths"
        fi

        # **MODIFICATION**: Use `basename` to strip directory paths.
        # `xargs -n 1 basename` runs the basename command for each line of input.
        local basenames
        basenames=$(echo "$paths_to_process" | xargs -n 1 basename)

        # Join the basenames with spaces to form the final image list.
        local image_list
        image_list=$(echo "$basenames" | tr '\n' ' ')
        image_list=${image_list% } # Trim trailing space

        # Add the "vm_name image1 image2..." string to our final array.
        if [[ -n "$image_list" ]]; then
            vm_backup_array+=("$vm_name $image_list")
        fi

    done < "$VM_LIST"

    # --- Final Output ---
    echo
    echo "--- Results: vm_backup_array ---"
    if [ ${#vm_backup_array[@]} -eq 0 ]; then
        echo "Array is empty. No VMs were processed successfully."
    else
        # Print each element of the array on a new line.
        printf "%s\n" "${vm_backup_array[@]}"
    fi
    echo "--------------------------------"
}

# --- To run the function, call it directly ---
vm_source_backup
