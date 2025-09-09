# Outpatient-System-Shell
Outpatient Reservation System
Linux Lab Project #1 Guide

1. Highlights
- Text-based interactive menu system
- Data persistence using plain text files
- Strong input validation and user-friendly prompts
- Separate patient and admin flows
- Logging of critical actions for traceability

2. Project Structure
patients.txt       - Stores registered patient data (Format: PatientID|Name|Phone)
doctors.txt        - Stores doctor details and working schedule (Format: DoctorID|Name|Specialty|WorkingDays|StartTime|EndTime)
appointments.txt   - Stores appointment records (Format: AppointmentID|PatientID|DoctorID|Date|Time|[Status])
admin.log          - Logs all admin actions (Human-readable timestamps)
patient.log        - Logs all patient actions (Human-readable timestamps)
main.sh            - Main script that runs the reservation system

3. How to Run
Make sure you are on a Unix/Linux system and have bash or sh:

chmod +x main.sh
./main.sh

You do not need to set execute permission on .txt files. The script will auto-create any missing files.

4. Features

Patients
- Register: Enter name and phone number; system generates a unique Patient ID (e.g. P001)
- Book Appointment:
  - Choose a specialty
  - Select a doctor and a valid date
  - Pick a time within their shift
  - Validates availability (30-minute slots)
- View Appointments:
  - View past and upcoming appointments separately
- Cancel Appointment:
  - Can only cancel future appointments
  - System logs cancellations

Admin
Login required (password: admin@123)

- Add New Doctor:
  - Inputs: Name, Specialty, Working Days (Sun–Sat), Shift Hours
  - Auto-generates a unique Doctor ID (e.g. D001)

- Update Doctor Schedule:
  - Modify specialty, working days, or shift times
  - Warns if upcoming appointments fall outside new shifts

- View Doctor Schedule:
  - Shows all appointments for a doctor by ID

5. Input Validations & Error Handling

The system ensures:
- Names follow First Last format (letters only)
- Phone numbers are digits (10–15 digits)
- IDs are validated (Pxxx, Dxxx, Axxx)
- Dates must be in the future
- Time must be in HH:MM format within doctor’s shift
- Prevents double-booking (for both doctor and patient)
- Disallows cancellation of past appointments

6. Logging System

admin.log: records every admin action (adding/updating doctor)
patient.log: tracks patient activities (registration, booking, cancellations)

Each log entry includes a timestamp and action description for easy auditing.

7. Notes

- The system is designed to run interactively in a terminal
