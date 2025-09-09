#!/bin/sh
register() {    
    #Read and validate name
    while true; do
        read -p "Enter patient's name (First and Last): " name

        #Remove leading and trailing spaces
        name="${name#"${name%%[![:space:]]*}"}"
        name="${name%"${name##*[![:space:]]}"}"

        #Validate: must be two words with letters only
        if ! [[ "$name" =~ ^[A-Za-z]+\ [A-Za-z]+$ ]]; then
            echo "Invalid name format. Use First Last with letters only."
            continue
        fi

        #Capitalize first letter of each name part
        first_name=$(echo "$name" | cut -d' ' -f1)
        last_name=$(echo "$name" | cut -d' ' -f2)
        name="$(tr '[:lower:]' '[:upper:]' <<< "${first_name:0:1}")${first_name:1} $(tr '[:lower:]' '[:upper:]' <<< "${last_name:0:1}")${last_name:1}"

        #Check for duplicates in patients.txt
        if matches=$(grep "|$name|" patients.txt); [ -n "$matches" ]; then
            echo "Warning: A patient named \"$name\" already exists:"
            echo "$matches"
            while true; do
                read -p "Do you still want to add another patient with this name? (y/n): " cont
                case "$cont" in
                    y|Y) break 2 ;;  #Proceed with duplicate
                    n|N) echo "Cancelled. Please enter a different name."; break ;;
                    *) echo "Invalid input. Enter y or n." ;;
                esac
            done
        else
            break
        fi
    done
        
    while true; do        
        read -p "Enter patient's phone number: " phone
        
        #Check if the phone number name has only digits
        if ! [[ "$phone" =~ ^[0-9]+$ ]]; then
            echo "Phone number must have only numeric value. Try again."
            continue
        fi
        
        #Check if the length of the number is valid
        if [ ${#phone} -lt 10 ] || [ ${#phone} -gt 15 ]; then
         echo "Phone number length is invalid. Make sure it's between (10-15)."
         continue
        fi
        break

    done

    #Confirm before saving
    echo ""
    echo "Please confirm the following details:"
    echo "Name: $name"
    echo "Phone Number: $phone"
    while true; do
        read -p "Save this patient? (y/n): " confirm
        case "$confirm" in
            y|Y) break ;;  # proceed
            n|N) echo "Patient addition cancelled."; return ;;
            *) echo "Invalid input. Please enter y or n." ;;
        esac
    done

    #Generate unique Patient ID by incrementing the last one
    patient_id=$(cut -d'|' -f1 "patients.txt" | grep '^P[0-9]\{3\}$' | sort | tail -n1)

    if [ -z "$patient_id" ]; then
        new_id="P001"
    else
        num=$(echo "$patient_id" | cut -c2-)
        num=$(expr "$num" + 1)
        case $num in
            [0-9])   new_id="P00$num" ;;
            [1-9][0-9]) new_id="P0$num" ;;
            *)       new_id="P$num" ;;
        esac
    fi

    echo "$new_id|$name|$phone" >> "patients.txt"
    echo "Patient $name added successfully with ID $new_id."
    echo ""

    #Logging
    log_time=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$log_time: Registered patient $name with ID $new_id" >> patient.log
}

book_appointment() {
    #Patient LOGIN
    while true; do
        read -p "Enter patient's ID (Pxxx): " id
        if ! [[ "$id" =~ ^P[0-9]{3}$ ]]; then
            echo "Invalid patient ID format. Format: (Pxxx)."
            continue
        fi
        if ! grep -iq "^$id|" patients.txt; then
            echo "Patient doesn't exist. Try again."
            continue
        fi
        break
    done

    #Show all available specialties
    av_spec=$(cut -d'|' -f3 doctors.txt | sort | uniq)
    echo "Available Specialties:"
    echo "$av_spec"

    # Specialty selection
    while true; do
        read -p "Enter the specialty you want: " spec
        if grep -iq "$spec" doctors.txt; then
            echo "Doctors matching specialty:"
            grep -i "$spec" doctors.txt | cut -d'|' -f1,2
            break
        else
            echo "No doctors available with this specialty. Try again."
        fi
    done

    #Doctor Selection
    while true; do
        read -p "Enter the ID of the doctor you want. Format (Dxxx): " doc
        if ! [[ "$doc" =~ ^D[0-9]{3}$ ]]; then
            echo "Invalid doctor ID format. Format: (Dxxx)."
            continue
        fi

        if grep -iq "^$doc|.*|$spec|" doctors.txt; then
            av_times=$(grep -i "^$doc|" doctors.txt | cut -d'|' -f4-6)
            echo "Shift days | Start time | End time"
            echo "$av_times" | tr '|' ' | '
            break
        else
            echo "This doctor does not belong to the selected specialty or doesn't exist. Try again."
        fi
    done

    #Date & Time Selection
    while true; do
        read -p "Enter date (YYYY-MM-DD): " date_input

        if date -j -f "%Y-%m-%d" "$date_input" "+%Y-%m-%d" >/dev/null 2>&1; then
            input_epoch=$(date -j -f "%Y-%m-%d" "$date_input" +"%s")
            now_epoch=$(date +"%s")
            if [ "$input_epoch" -lt "$now_epoch" ]; then
                echo "You cannot book an appointment in the past. Enter a future date."
                continue
            fi

            chosen_day=$(date -j -f "%Y-%m-%d" "$date_input" +"%a")
            shift_day=$(echo "$av_times" | cut -d'|' -f1)
            if echo "$shift_day" | grep -qw "$chosen_day"; then
                echo "Day is available in the doctor's shift."

                while true; do
                    shift_start_raw=$(echo "$av_times" | cut -d'|' -f2)
                    shift_end_raw=$(echo "$av_times" | cut -d'|' -f3)

                    shift_start_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$date_input $shift_start_raw" "+%s")
                    shift_end_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$date_input $shift_end_raw" "+%s")

                    has_free_slot=0
                    t=$shift_start_epoch

                    while [ "$t" -le "$((shift_end_epoch - 1800))" ]; do
                        conflict_found=0
                        while IFS='|' read -r _ _ doc_id app_date app_time; do
                            if [[ "$doc_id" == "$doc" && "$app_date" == "$date_input" ]]; then
                                booked_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$app_date $app_time" "+%s" 2>/dev/null)
                                if [ -n "$booked_epoch" ]; then
                                    diff=$(( t - booked_epoch ))
                                    diff=${diff#-}
                                    if [ "$diff" -lt 1800 ]; then
                                        conflict_found=1
                                        break
                                    fi
                                fi
                            fi
                        done < appointments.txt

                        if [ "$conflict_found" -eq 0 ]; then
                            has_free_slot=1
                            break
                        fi

                        t=$((t + 60))
                    done

                    if [ "$has_free_slot" -eq 0 ]; then
                        echo "The doctor has no available time slots on this day. Please choose another date."
                        break
                    fi

                    read -p "Choose a time in this range $shift_start_raw to $shift_end_raw. Format (HH:MM): " time_input

                    if [[ "$time_input" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                        selected_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$date_input $time_input" "+%s" 2>/dev/null)
                        if [ -z "$selected_epoch" ]; then
                            echo "Invalid date or time."
                            continue
                        fi

                        if [ "$selected_epoch" -lt "$shift_start_epoch" ]; then
                            echo "This time is before the doctor's shift start ($shift_start_raw). Please enter a later time."
                            continue
                        elif [ "$selected_epoch" -gt "$shift_end_epoch" ]; then
                            echo "This time is after the doctor's shift end ($shift_end_raw). Please enter an earlier time."
                            continue
                        fi

                        conflict_found=0
                        while IFS='|' read -r _ patient_id_loop doc_id app_date app_time; do
                            if [[ "$app_date" == "$date_input" ]]; then
                                booked_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$app_date $app_time" "+%s" 2>/dev/null)
                                if [ -n "$booked_epoch" ]; then
                                    diff=$(( selected_epoch - booked_epoch ))
                                    diff=${diff#-}

                                    #Check conflict with same doctor OR same patient at same time
                                    if { [ "$doc_id" == "$doc" ] || [ "$patient_id_loop" == "$id" ]; } && [ "$diff" -lt 1800 ]; then
                                        conflict_found=1
                                        break
                                    fi
                                fi
                            fi
                        done < appointments.txt


                        if [ "$conflict_found" -eq 1 ]; then
                            echo "This slot or a nearby time is already booked. Choose another time."
                            continue
                        fi

                        echo "The following slot is available:"
                        echo "Doctor: $doc"
                        echo "Date  : $date_input"
                        echo "Time  : $time_input"

                        while true; do
                            read -p "Do you want to confirm this appointment? (y/n): " confirm
                            case "$confirm" in
                                y|Y)
                                    appointment_id=$(cut -d'|' -f1 appointments.txt | grep '^A[0-9]\{3\}$' | sort | tail -n1)
                                    if [ -z "$appointment_id" ]; then
                                        new_id="A001"
                                    else
                                        num=$(echo "$appointment_id" | cut -c2-)
                                        num=$((num + 1))
                                        case $num in
                                            [0-9])     new_id="A00$num" ;;
                                            [1-9][0-9]) new_id="A0$num" ;;
                                            *)         new_id="A$num" ;;
                                        esac
                                    fi
                                    app="$new_id|$id|$doc|$date_input|$time_input"
                                    echo "$app" >> appointments.txt
                                    echo "Appointment confirmed and saved:"
                                    echo "$app"
                                    echo ""

                                    #Logging
                                    log_time=$(date "+%Y-%m-%d %H:%M:%S")
                                    echo "$log_time: Patient $id booked appointment $new_id with Doctor $doc on $date_input at $time_input" >> patient.log
                                    break 3
                                    ;;
                                n|N)
                                    echo "Appointment cancelled. Choose a different time or date."
                                    break
                                    ;;
                                *)
                                    echo "Invalid input. Enter y or n."
                                    ;;
                            esac
                        done
                    else
                        echo "Invalid time format. Format: HH:MM."
                    fi
                done
            else
                echo "This day is not in the doctor's shift. Choose another date."
            fi
        else
            echo "Invalid date format. Format: YYYY-MM-DD."
        fi
    done
}

view_appointments() {
    #Patient login
    while true; do
        read -p "Enter patient's ID (PXXX): " id

        if ! [[ "$id" =~ ^P[0-9]{3}$ ]]; then
            echo "Invalid patient ID format. Format: (PXXX)."
            continue
        fi

        if ! grep -iq "^$id|" patients.txt; then
            echo "Patient doesn't exist. Try again."
            continue
        fi
        break
    done

    #Get today's date and convert to epoch
    today_date=$(date +%Y-%m-%d)
    today_epoch=$(date -j -f "%Y-%m-%d" "$today_date" +%s)

    found_upcoming=0
    found_past=0
    has_any=0

    echo "Upcoming Appointments:"
    while IFS='|' read -r app_id patient_id doctor_id date time
    do
        clean_id=$(echo "$patient_id" | tr -d '\r' | tr -d ' ')
        if [ "$clean_id" = "$id" ]; then
            has_any=1
            clean_date=$(echo "$date" | tr -d '\r' | tr -d ' ')
            app_epoch=$(date -j -f "%Y-%m-%d" "$clean_date" +%s 2>/dev/null)

            if [ -n "$app_epoch" ] && [ "$app_epoch" -ge "$today_epoch" ]; then
                echo "$app_id | Doctor: $doctor_id | Date: $clean_date | Time: $time"
                found_upcoming=1
            fi
        fi
    done < appointments.txt

    if [ "$found_upcoming" -eq 0 ]; then
        echo "No upcoming appointments."
    fi

    echo
    echo "Past Appointments:"
    while IFS='|' read -r app_id patient_id doctor_id date time
    do
        clean_id=$(echo "$patient_id" | tr -d '\r' | tr -d ' ')
        if [ "$clean_id" = "$id" ]; then
            has_any=1
            clean_date=$(echo "$date" | tr -d '\r' | tr -d ' ')
            app_epoch=$(date -j -f "%Y-%m-%d" "$clean_date" +%s 2>/dev/null)

            if [ -n "$app_epoch" ] && [ "$app_epoch" -lt "$today_epoch" ]; then
                echo "$app_id | Doctor: $doctor_id | Date: $clean_date | Time: $time"
                found_past=1
            fi
        fi
    done < appointments.txt

    if [ "$found_past" -eq 0 ]; then
        echo "No past appointments."
        echo ""
    fi

    if [ "$has_any" -eq 0 ]; then
        echo "No appointments found for this patient."
    fi
}

cancel_appointment() {
    #Patient login
    while true; do
        read -p "Enter patient's ID (PXXX): " id

        if ! [[ "$id" =~ ^P[0-9]{3}$ ]]; then
            echo "Invalid patient ID format. Format: (PXXX)."
            continue
        fi

        if ! grep -iq "^$id|" patients.txt; then
            echo "Patient doesn't exist. Try again."
            continue
        fi
        break
    done

    #Check if patient has any appointments
    patient_appointments=$(grep -i "|$id|" appointments.txt)
    if [ -z "$patient_appointments" ]; then
        echo "No appointments to cancel."
        return
    fi

    echo "Appointments:"
    IFS=$'\n'
    for line in $patient_appointments; do
        IFS='|' read -r app_id _ doctor date time status <<< "$line"
        echo "$app_id | Doctor: $doctor | Date: $date | Time: $time | Status: ${status:-Scheduled}"
    done

    #Appointment selection
    while true; do
        read -p "Enter the appointment ID to cancel (AXXX): " appid

        if ! [[ "$appid" =~ ^A[0-9]{3}$ ]]; then
            echo "Invalid appointment ID format. Format: (AXXX)."
            continue
        fi

        #Check appointment exists and belongs to patient
        chosen_appointment=$(grep -i "^$appid|$id|" appointments.txt)
        if [ -z "$chosen_appointment" ]; then
            echo "Appointment not found for this patient. Try again."
            continue
        fi

        # Extract fields
        IFS='|' read -r found_appid found_id doctor date time status <<< "$chosen_appointment"

        # Check if already cancelled
        if [ "$status" = "Cancelled" ]; then
            echo "This appointment is already cancelled. Cannot cancel again."
            continue
        fi

        # Date check
        today=$(date +%Y-%m-%d)
        if [[ "$date" < "$today" ]]; then
            echo "Cannot cancel a past appointment."
            continue
        fi

        # Confirm cancel
        echo "Are you sure you want to cancel this appointment?"
        echo "$chosen_appointment"
        read -p "Confirm cancellation? (y/n): " confirm
        case "$confirm" in
            y|Y)
                new_cancel="$found_appid|$found_id|$doctor|$date|$time|Cancelled"
                sed -i '' "s#$(echo "$chosen_appointment" | sed 's/[&/\]/\\&/g')#$new_cancel#" appointments.txt
                echo "Appointment cancelled successfully."
                echo ""

                log_time=$(date "+%Y-%m-%d %H:%M:%S")
                echo "$log_time: Patient $id cancelled appointment $appid" >> patient.log
                break
                ;;
            n|N)
                echo "Cancellation aborted."
                echo ""
                break
                ;;
            *)
                echo "Invalid input. Enter y or n."
                ;;
        esac
    done
}

add_new_doctor() {
    doctors_file="doctors.txt"
    log_file="admin.log"

    [ ! -f "$doctors_file" ] && touch "$doctors_file"

    #Read and validate name
    while true; do
        read -p "Enter doctor's name (First and Last): " name

        #Remove leading and trailing spaces
        name="${name#"${name%%[![:space:]]*}"}"
        name="${name%"${name##*[![:space:]]}"}"

        #Validate: must be two words with letters only
        if ! [[ "$name" =~ ^[A-Za-z]+\ [A-Za-z]+$ ]]; then
            echo "Invalid name format. Use First Last with letters only."
            continue
        fi

        #Capitalize first letter of each name part
        first_name=$(echo "$name" | cut -d' ' -f1)
        last_name=$(echo "$name" | cut -d' ' -f2)
        name="$(tr '[:lower:]' '[:upper:]' <<< "${first_name:0:1}")${first_name:1} $(tr '[:lower:]' '[:upper:]' <<< "${last_name:0:1}")${last_name:1}"

        #Check for duplicates in doctors_file
        if matches=$(grep "|$name|" "$doctors_file"); [ -n "$matches" ]; then
            echo "Warning: A doctor named \"$name\" already exists:"
            echo "$matches"
            while true; do
                read -p "Do you still want to add another doctor with this name? (y/n): " cont
                case "$cont" in
                    y|Y) break 2 ;;  #Proceed with duplicate
                    n|N) echo "Cancelled. Please enter a different name."; break ;;
                    *) echo "Invalid input. Enter y or n." ;;
                esac
            done
        else
            break
        fi
    done

    #Specialty
    while true; do
        read -p "Enter doctor's specialty: " specialty
        echo "$specialty" | grep -Eq '^[A-Za-z ]+$' && break || echo "Specialty must contain only letters and spaces."
    done

    #Working days
    while true; do
        read -p "Enter working days (comma-separated, e.g. Sun, Mon, Tue): " days_raw

        working_days=""
        dup_check=""
        valid=1

        IFS=',' read -ra days_array <<< "$days_raw"
        for d in "${days_array[@]}"; do
            trimmed=$(echo "$d" | sed 's/^ *//;s/ *$//')
            first_char=$(echo "$trimmed" | cut -c1 | tr 'a-z' 'A-Z')
            rest_chars=$(echo "$trimmed" | cut -c2- | tr 'A-Z' 'a-z')
            formatted="$first_char$rest_chars"

            case "$formatted" in
                Sun|Mon|Tue|Wed|Thu|Fri|Sat)
                    echo "$dup_check" | grep -w "$formatted" >/dev/null && { echo "Duplicate day: $formatted"; valid=0; break; }
                    dup_check="$dup_check $formatted"
                    [ -z "$working_days" ] && working_days="$formatted" || working_days="$working_days,$formatted"
                    ;;
                *) echo "Invalid day: $formatted. Format: (Sun, Mon, Tue)."; valid=0; break ;;
            esac
        done

        [ "$valid" -eq 1 ] && [ -n "$working_days" ] && break
    done

    #Start time
    while true; do
        read -p "Enter start time (HH:MM): " start

        if echo "$start" | grep -qE '^[0-9]{2}:[0-9]{2}$'; then
            hh=$(echo "$start" | cut -d':' -f1)
            mm=$(echo "$start" | cut -d':' -f2)

            #Ensure hh and mm are numeric
            if [[ "$hh" =~ ^[0-9]{2}$ ]] && [[ "$mm" =~ ^[0-9]{2}$ ]]; then
                hh_val=$(echo "$hh" | sed 's/^0*//')
                mm_val=$(echo "$mm" | sed 's/^0*//')

                hh_val=${hh_val:-0}
                mm_val=${mm_val:-0}

                if [ "$hh_val" -ge 0 ] && [ "$hh_val" -le 23 ] && [ "$mm_val" -ge 0 ] && [ "$mm_val" -le 59 ]; then
                    break
                fi
            fi
        fi

        echo "Invalid start time format. Format: (HH:MM)."
    done

    #End time
    while true; do
        read -p "Enter end time (HH:MM): " end

        if echo "$end" | grep -qE '^[0-9]{2}:[0-9]{2}$'; then
            hh2=$(echo "$end" | cut -d':' -f1)
            mm2=$(echo "$end" | cut -d':' -f2)

            if [[ "$hh2" =~ ^[0-9]{2}$ ]] && [[ "$mm2" =~ ^[0-9]{2}$ ]]; then
                hh2_val=$(echo "$hh2" | sed 's/^0*//')
                mm2_val=$(echo "$mm2" | sed 's/^0*//')

                hh2_val=${hh2_val:-0}
                mm2_val=${mm2_val:-0}

                if [ "$hh2_val" -ge 0 ] && [ "$hh2_val" -le 23 ] && [ "$mm2_val" -ge 0 ] && [ "$mm2_val" -le 59 ]; then
                    if [[ "$end" > "$start" ]]; then
                        break
                    else
                        echo "End time must be after start time."
                        continue
                    fi
                fi
            fi
        fi

        echo "Invalid end time format. Format: (HH:MM)."
    done

    #Confirm
    echo ""
    echo "Please confirm the following details:"
    echo "Name: $name"
    echo "Specialty: $specialty"
    echo "Working Days: $working_days"
    echo "Working Hours: $start - $end"
    while true; do
        read -p "Save this doctor? (y/n): " confirm
        case "$confirm" in
            y|Y) break ;;
            n|N) echo "Doctor addition cancelled."; return ;;
            *) echo "Invalid input. Please enter y or n." ;;
        esac
    done

    #Generate ID
    last_id=$(cut -d'|' -f1 "$doctors_file" | grep '^D[0-9]\{3\}$' | sort | tail -n1)
    if [ -z "$last_id" ]; then
        new_id="D001"
    else
        num=$(echo "$last_id" | cut -c2-)
        num=$(expr "$num" + 1)
        new_id=$(printf "D%03d" "$num")
    fi

    echo "$new_id|$name|$specialty|$working_days|$start|$end" >> "$doctors_file"
    echo "Doctor $name added successfully with ID $new_id."
    echo ""

    #Log
    now=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$now: Added doctor $name with ID $new_id" >> "$log_file"
}

update_doctor_schedule() {
    doctors_file="doctors.txt"
    appointments_file="appointments.txt"
    temp_file="doctors_temp.txt"
    log_file="admin.log"

    if [ ! -f "$doctors_file" ]; then
        echo "$doctors_file not found."
        return
    fi

    read -p "Enter Doctor ID to update (e.g. D001): " doc_id

    #Search for doctor
    doctor_line=$(grep "^$doc_id|" "$doctors_file")
    if [ -z "$doctor_line" ]; then
        echo "Doctor with ID $doc_id not found."
        return
    fi

    name=$(echo "$doctor_line" | cut -d'|' -f2)
    specialty=$(echo "$doctor_line" | cut -d'|' -f3)
    working_days=$(echo "$doctor_line" | cut -d'|' -f4)
    start_time=$(echo "$doctor_line" | cut -d'|' -f5)
    end_time=$(echo "$doctor_line" | cut -d'|' -f6)

    while true; do
        echo ""
        echo "Select what you want to update:"
        echo "1. Specialty."
        echo "2. Working Days."
        echo "3. Working Hours."
        echo "4. Finish Updating."
        read -p "Enter choice (1-4): " choice

        case "$choice" in
            1)
                read -p "Enter new specialty: " new_specialty
                if echo "$new_specialty" | grep -Eq '^[A-Za-z ]+$'; then
                    specialty="$new_specialty"
                else
                    echo "Invalid specialty format."
                fi
                ;;

            2)
                read -p "Enter new working days (comma-separated: Sun, Mon, Tue): " input_days
                new_days=""
                dup_check=""
                valid=1
                echo "$input_days" | tr ',' '\n' | while read d; do
                    first=$(echo "$d" | cut -c1 | tr 'a-z' 'A-Z')
                    rest=$(echo "$d" | cut -c2- | tr 'A-Z' 'a-z')
                    day="$first$rest"
                    case "$day" in
                        Sun|Mon|Tue|Wed|Thu|Fri|Sat)
                            if echo "$dup_check" | grep -qw "$day"; then
                                echo "Duplicate day: $day"
                                valid=0
                                exit
                            fi
                            dup_check="$dup_check $day"
                            if [ -z "$new_days" ]; then
                                new_days="$day"
                            else
                                new_days="$new_days,$day"
                            fi
                            ;;
                        *)
                            echo "Invalid day: $day"
                            valid=0
                            exit
                            ;;
                    esac
                done
                if [ "$valid" = 1 ] && [ -n "$new_days" ]; then
                    working_days="$new_days"
                fi
                ;;

            3)
                while true; do
                    read -p "Enter new start time (HH:MM): " new_start
                    h1=$(echo "$new_start" | cut -d':' -f1)
                    m1=$(echo "$new_start" | cut -d':' -f2)
                    if [ ${#h1} -eq 2 ] && [ ${#m1} -eq 2 ]; then
                        hv=$(expr "$h1" + 0)
                        mv=$(expr "$m1" + 0)
                        if [ "$hv" -ge 0 ] && [ "$hv" -le 23 ] && [ "$mv" -ge 0 ] && [ "$mv" -le 59 ]; then
                            start_time="$new_start"
                            break
                        fi
                    fi
                    echo "Invalid time format."
                done

                while true; do
                    read -p "Enter new end time (HH:MM): " new_end
                    h2=$(echo "$new_end" | cut -d':' -f1)
                    m2=$(echo "$new_end" | cut -d':' -f2)
                    if [ ${#h2} -eq 2 ] && [ ${#m2} -eq 2 ]; then
                        hv2=$(expr "$h2" + 0)
                        mv2=$(expr "$m2" + 0)
                        if [ "$hv2" -ge 0 ] && [ "$hv2" -le 23 ] && [ "$mv2" -ge 0 ] && [ "$mv2" -le 59 ]; then
                            if [ "$new_end" \> "$start_time" ]; then
                                end_time="$new_end"
                                break
                            else
                                echo "End time must be after start time."
                            fi
                        fi
                    fi
                    echo "Invalid time format."
                done

                if [ -f "$appointments_file" ]; then
                    grep "^$doc_id|" "$appointments_file" | while read appt; do
                        appt_time=$(echo "$appt" | cut -d'|' -f4)
                        if [ "$appt_time" \< "$start_time" ] || [ "$appt_time" \> "$end_time" ]; then
                            echo "Warning: appointment outside new working hours: $appt"
                        fi
                    done
                fi
                ;;

            4)
                break
                ;;
            *)
                echo "Invalid choice."
                ;;
        esac
    done

    #Rewrite file
    while read line; do
        curr_id=$(echo "$line" | cut -d'|' -f1)
        if [ "$curr_id" = "$doc_id" ]; then
            echo "$doc_id|$name|$specialty|$working_days|$start_time|$end_time" >> "$temp_file"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$doctors_file"

    mv "$temp_file" "$doctors_file"
    echo "Doctor record updated successfully."
    echo ""

    #Log
    now=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$now: Updated doctor $doc_id" >> "$log_file"
}

view_doctor_schedule() {
    doctors_file="doctors.txt"
    appointments_file="appointments.txt"

    #Check if required files exist
    if [ ! -f "$doctors_file" ]; then
        echo "$doctors_file not found."
        return
    fi

    if [ ! -f "$appointments_file" ]; then
        echo "$appointments_file not found."
        return
    fi

    #Input Doctor ID
    read -p "Enter Doctor ID to view schedule (e.g. D001): " doc_id

    #Check if doctor exists
    line=$(grep "^$doc_id|" "$doctors_file")
    if [ -z "$line" ]; then
        echo "Doctor with ID $doc_id not found."
        return
    fi

    #Get doctor info
    name=$(echo "$line" | cut -d'|' -f2)
    specialty=$(echo "$line" | cut -d'|' -f3)

    echo ""
    echo "Doctor: $name"
    echo "Specialty: $specialty"
    echo ""
    echo "Appointments:"

    #Check if doctor has any non-cancelled appointments
    has_appointments=0
    while IFS='|' read -r app_id patient_id d_id date time status; do
        if [ "$d_id" = "$doc_id" ] && [ "$status" != "Cancelled" ]; then
            has_appointments=1
            break
        fi
    done < "$appointments_file"

    if [ "$has_appointments" -eq 0 ]; then
        echo "Doctor $doc_id has no appointments."
        echo ""
        return
    fi

    #Print only non-cancelled appointments
    while IFS='|' read -r app_id patient_id doctor_id date time status; do
        if [ "$doctor_id" = "$doc_id" ] && [ "$status" != "Cancelled" ]; then
            echo "$app_id | Doctor: $doctor_id | Patient: $patient_id | Date: $date | Time: $time"
        fi
    done < "$appointments_file"
}

patients_menu(){
    if [ ! -e patients.txt ]; then
        touch patients.txt
    fi
     if [ ! -e doctors.txt ]; then
        touch doctors.txt
    fi
    if [ ! -e appointments.txt ]; then
        touch appointments.txt
    fi
    if [ ! -e patient.log ]; then
        touch patient.log
    fi

    while true; do
        echo "Select an operation (1-5):"
        echo "1. Register New Patient."
        echo "2. Book an Appointment."
        echo "3. View your Appointment."
        echo "4. Cancel your Appointment."
        echo "5. Exit Patient Menu."
        read -p "Enter your choice: " choice
        
        case "$choice" in
        1) register ;;
        2) book_appointment;;
        3) view_appointments;;
        4) cancel_appointment;;
        5) echo "Returning to main menu..."
           main_menu;;
        *) echo "Invalid choice, Please enter a number (1-5)";;
            
        esac
    done
}

pass="admin@123"
admin_menu() {
    if [ ! -e patients.txt ]; then
        touch patients.txt
    fi
     if [ ! -e doctors.txt ]; then
        touch doctors.txt
    fi
    if [ ! -e appointments.txt ]; then
        touch appointments.txt
    fi
    if [ ! -e admin.log ]; then
        touch admin.log
    fi

    while true; do
        echo "Select an operation (1-4):"
        echo "1. Add New Doctor."
        echo "2. Update Doctor Schedule."
        echo "3. View Doctor's Schedule."
        echo "4. Exit Admin Menu."
        read -p "Enter your choice: " choice

        case "$choice" in
            1) add_new_doctor;;
            2) update_doctor_schedule;;
            3) view_doctor_schedule;;
            4) echo "Returning to main menu..."
               main_menu;;
            *) echo "Invalid choice. Please enter a number (1-4).";;
        esac
    done
}

main_menu() {
    while true; do
        echo ""
        echo "Welcome to Outpatient Reservation System!"
        echo "PLEASE CHOOSE YOUR ROLE (1-3): "
        echo "1. Patient."
        echo "2. Admin."
        echo "3. Exit the system."
        read -p "Enter your choice: " answer

        case "$answer" in
            1)  echo ""
                echo "Welcome to Patient Menu:" 
                patients_menu ;;
            2)  while true; do
                    read -sp "Enter admin password (or 'q' to go back): " admin_pass
                    if [ "$admin_pass" = "$pass" ]; then
                        echo ""
                        echo ""
                        echo "Welcome to Admin Menu:"
                        admin_menu
                        break
                    elif [ "$admin_pass" = "q" ]; then
                        echo "Returning to main menu..."
                        break
                    else
                        echo "Password is incorrect. Try again or type 'q' to go back."
                    fi
                done
                ;;
            3)  echo "Exiting the system... Goodbye!"
                exit 1;;
            *)  echo "Invalid choice. Please enter a number (1-3).";;
        esac
    done
}
main_menu