PROGRAM_NAME='MasterCode'
(***********************************************************)
(* KEY HISTORY:                                            *)
(*                                                         *)
(* v1.0 - Initial build                                    *)
(* v1.1 - Added heartbeat, confirmed feedback, retry logic *)
(* v1.2 - Fixed Optoma command format XX -> 00             *)
(* v1.3 - Fixed status query ~00124 1, response Ok0/Ok1   *)
(* v2.0 - Switched to RS-232 serial control               *)
(* v2.1 - Changed to RS-232 port 4                        *)
(* v2.2 - Multi-state feedback, button disable, status bar *)
(* v2.3 - Fixed state machine: consistent on[]/off[] + ANI *)
(*         Bug: Ok1 ON=^ANI-20,3,3,0 OFF=^ANI-21,3,3,0   *)
(*         Bug: INFO1 removed nProjectorPower guard        *)
(*         Bug: HOME button now uses all 3 states          *)
(*         Bug: Removed duplicate dead-code ANI calls      *)
(***********************************************************)

(***********************************************************)
(*               DEVICE NUMBER DEFINITIONS                 *)
(***********************************************************)
DEFINE_DEVICE

// AMX MXT-1001 G5 Touch Panel -- 192.168.21.12
dvTP            = 10001:1:0

// Optoma EH415E Projector -- RS-232 -- NX-3200 Port 4
dvProjector     = 5001:4:0

(***********************************************************)
(*                CONSTANT DEFINITIONS                     *)
(***********************************************************)
DEFINE_CONSTANT

(* --------------------------------------------------------*)
(* TOUCH PANEL -- HOME PAGE                                *)
(* --------------------------------------------------------*)
BTN_SYS_POWER_ON        = 1

(* --------------------------------------------------------*)
(* TOUCH PANEL -- DISPLAY PAGE                             *)
(* --------------------------------------------------------*)
BTN_PROJ_PWR_ON         = 20
BTN_PROJ_PWR_OFF        = 21
BTN_INP_HDMI            = 22
BTN_INP_VGA             = 23
BTN_INP_HDMI2           = 24
BTN_PROJ_FREEZE         = 25
BTN_PROJ_BLANK          = 26

(* --------------------------------------------------------*)
(* TOUCH PANEL -- NAVIGATION                               *)
(* --------------------------------------------------------*)
BTN_NAV_HOME            = 101
BTN_NAV_DISPLAY         = 102
BTN_NAV_AUDIO           = 103
BTN_NAV_PRESETS         = 104

(* --------------------------------------------------------*)
(* STATUS BAR                                              *)
(* --------------------------------------------------------*)
TXT_STATUS              = 200

(***********************************************************)
(*              BUTTON STATE REFERENCE                     *)
(*                                                         *)
(*  BTN_PROJ_PWR_ON (20):                                  *)
(*    State 1 = GRAY          (projector off)              *)
(*    State 2 = AMBER         (warming up)                 *)
(*    State 3 = GREEN         (projector on)               *)
(*                                                         *)
(*  BTN_PROJ_PWR_OFF (21):                                 *)
(*    State 1 = RED           (projector off -- status)    *)
(*    State 2 = DIMMED GREEN  (cooling down)               *)
(*    State 3 = GRAY          (projector on -- available)  *)
(*                                                         *)
(*  BTN_SYS_POWER_ON (1):                                  *)
(*    State 1 = GRAY          (system off)                 *)
(*    State 2 = AMBER         (transitioning)              *)
(*    State 3 = GREEN         (system on)                  *)
(*                                                         *)
(*  STATE MACHINE:                                         *)
(*    PROJ OFF : ON=St1  OFF=St1  HOME=St1                 *)
(*    WARMING  : ON=St2  OFF=St3  HOME=St2                 *)
(*    PROJ ON  : ON=St3  OFF=St3  HOME=St3                 *)
(*    COOLING  : ON=St1  OFF=St2  HOME=St2                 *)
(***********************************************************)

(***********************************************************)
(*                VARIABLE DEFINITIONS                     *)
(***********************************************************)
DEFINE_VARIABLE

volatile integer nSystemPower       // 0=off, 1=on
volatile integer nProjectorPower    // 0=off, 1=on
volatile integer nLastCommand       // 1=power on, 0=power off

volatile long lHeartbeat[] = {30000}   // 30 second heartbeat

(***********************************************************)
(*                     STARTUP CODE                        *)
(***********************************************************)
DEFINE_START

send_string 0, "'SYSTEM STARTED v2.3'"

// Configure RS-232 port 4
send_command dvProjector, "'SET BAUD 9600 N 8 1'"
send_command dvProjector, "'CLEAR_FAULT'"

// STATE: PROJECTOR OFF
// ON button  -> GRAY (State 1)
off[dvTP, BTN_PROJ_PWR_ON]
send_command dvTP, "'^ANI-20,1,1,0'"

// OFF button -> RED (State 1)
off[dvTP, BTN_PROJ_PWR_OFF]
send_command dvTP, "'^ANI-21,1,1,0'"

// HOME button -> GRAY (State 1)
off[dvTP, BTN_SYS_POWER_ON]
send_command dvTP, "'^ANI-1,1,1,0'"

// Disable input and control buttons on boot
send_command dvTP, "'^ENA-22,0'"
send_command dvTP, "'^ENA-23,0'"
send_command dvTP, "'^ENA-24,0'"
send_command dvTP, "'^ENA-25,0'"
send_command dvTP, "'^ENA-26,0'"

// Status bar
send_command dvTP, "'^TXT-200,0,System OFF'"
send_command dvTP, "'^CFT-200,0,2,#E74C3C'"

// Start heartbeat
timeline_create(1, lHeartbeat, 1, TIMELINE_RELATIVE, TIMELINE_REPEAT)

(***********************************************************)
(*                     EVENT HANDLERS                      *)
(***********************************************************)
DEFINE_EVENT

(* --------------------------------------------------------*)
(* HEARTBEAT -- POLL PROJECTOR STATE                       *)
(* --------------------------------------------------------*)
timeline_event[1]
{
    send_string dvProjector, "'~00124 1', $0D"
    send_string 0, "'Heartbeat - status query sent'"
}

(* --------------------------------------------------------*)
(* PROJECTOR -- RS-232 RESPONSE HANDLER                    *)
(* --------------------------------------------------------*)
data_event[dvProjector]
{
    string:
    {
        send_string 0, "'RAW: [', data.text, ']'"

        // --- PROJECTOR ON ---
        if (find_string(data.text, 'Ok1', 1))
        {
            nProjectorPower = 1
            nSystemPower    = 1

            // ON button  -> GREEN (State 3)
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,3,3,0'"

            // OFF button -> GRAY (State 3)
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,3,3,0'"

            // HOME button -> GREEN (State 3)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,3,3,0'"

            // Enable input/control buttons
            send_command dvTP, "'^ENA-22,1'"
            send_command dvTP, "'^ENA-23,1'"
            send_command dvTP, "'^ENA-24,1'"
            send_command dvTP, "'^ENA-25,1'"
            send_command dvTP, "'^ENA-26,1'"

            send_command dvTP, "'^TXT-200,0,Projector ON'"
            send_command dvTP, "'^CFT-200,0,2,#2ECC71'"
            send_string 0, "'Projector confirmed: ON'"
        }

        // --- PROJECTOR OFF ---
        else if (find_string(data.text, 'Ok0', 1))
        {
            nProjectorPower = 0
            nSystemPower    = 0

            // ON button  -> GRAY (State 1)
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,1,1,0'"

            // OFF button -> RED (State 1)
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,1,1,0'"

            // HOME button -> GRAY (State 1)
            off[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,1,1,0'"

            // Disable input/control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,System OFF'"
            send_command dvTP, "'^CFT-200,0,2,#E74C3C'"
            send_string 0, "'Projector confirmed: OFF'"
        }

        // --- WARMING UP (INFO1) ---
        else if (find_string(data.text, 'INFO1', 1))
        {
            // No nProjectorPower guard here -- it was set optimistically
            // on button push, so the old check never fired. Always show warming.

            // ON button  -> AMBER (State 2)
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,2,2,0'"

            // OFF button -> GRAY (State 3) -- not available during warm-up
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,3,3,0'"

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input/control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Warming Up'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"
            send_string 0, "'INFO1 received -- projector warming up'"
            wait 100 { send_string dvProjector, "'~00124 1', $0D" }
        }

        // --- COOLING DOWN (INFO2) ---
        else if (find_string(data.text, 'INFO2', 1))
        {
            // ON button  -> GRAY (State 1)
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,1,1,0'"

            // OFF button -> DIMMED GREEN (State 2)
            on[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,2,2,0'"

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input/control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Cooling Down'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"
            send_string 0, "'Projector cooling down (INFO2)'"
            wait 100 { send_string dvProjector, "'~00124 1', $0D" }
        }

        // --- COMMAND ACCEPTED ---
        else if (find_string(data.text, 'P', 1))
        {
            send_string 0, "'Command accepted -- querying state...'"
            wait 50 { send_string dvProjector, "'~00124 1', $0D" }
        }
    }
}

(* --------------------------------------------------------*)
(* HOME PAGE -- SYSTEM POWER TOGGLE                        *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_SYS_POWER_ON]
{
    push:
    {
        if (nSystemPower == 0)
        {
            // TURN ON -- show WARMING state
            nLastCommand    = 1
            send_string dvProjector, "'~0000 1', $0D"

            // ON button  -> AMBER (State 2)
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,2,2,0'"

            // OFF button -> GRAY (State 3)
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,3,3,0'"

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input/control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Starting...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nSystemPower    = 1
            nProjectorPower = 1
            wait 30 { send_string dvProjector, "'~00124 1', $0D" }
        }
        else
        {
            // TURN OFF -- show COOLING state
            nLastCommand    = 0
            send_string dvProjector, "'~0000 0', $0D"

            // ON button  -> GRAY (State 1)
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,1,1,0'"

            // OFF button -> DIMMED GREEN (State 2)
            on[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,2,2,0'"

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input/control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Shutting Down...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nSystemPower    = 0
            nProjectorPower = 0
            wait 30 { send_string dvProjector, "'~00124 1', $0D" }
        }
    }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- PROJECTOR POWER ON                      *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_PWR_ON]
{
    push:
    {
        if (nProjectorPower == 0)
        {
            nLastCommand = 1
            send_string dvProjector, "'~0000 1', $0D"

            // ON button  -> AMBER (State 2)
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,2,2,0'"

            // OFF button -> GRAY (State 3)
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,3,3,0'"

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input/control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Starting...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nProjectorPower = 1
            nSystemPower    = 1
            wait 30 { send_string dvProjector, "'~00124 1', $0D" }
        }
    }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- PROJECTOR POWER OFF                     *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_PWR_OFF]
{
    push:
    {
        if (nProjectorPower == 1)
        {
            nLastCommand = 0
            send_string dvProjector, "'~0000 0', $0D"

            // ON button  -> GRAY (State 1)
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,1,1,0'"

            // OFF button -> DIMMED GREEN (State 2)
            on[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,2,2,0'"

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input/control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Shutting Down...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nProjectorPower = 0
            nSystemPower    = 0
            wait 30 { send_string dvProjector, "'~00124 1', $0D" }
        }
    }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- INPUT SELECTION                         *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_INP_HDMI]
{
    push:
    {
        send_string dvProjector, "'~0012 5', $0D"
        on[dvTP,  BTN_INP_HDMI]
        off[dvTP, BTN_INP_VGA]
        off[dvTP, BTN_INP_HDMI2]
    }
}

button_event[dvTP, BTN_INP_VGA]
{
    push:
    {
        send_string dvProjector, "'~0012 1', $0D"
        off[dvTP, BTN_INP_HDMI]
        on[dvTP,  BTN_INP_VGA]
        off[dvTP, BTN_INP_HDMI2]
    }
}

button_event[dvTP, BTN_INP_HDMI2]
{
    push:
    {
        send_string dvProjector, "'~0012 6', $0D"
        off[dvTP, BTN_INP_HDMI]
        off[dvTP, BTN_INP_VGA]
        on[dvTP,  BTN_INP_HDMI2]
    }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- FREEZE TOGGLE                           *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_FREEZE]
{
    push:
    {
        if ([dvTP, BTN_PROJ_FREEZE])
        {
            send_string dvProjector, "'~0080 0', $0D"
            off[dvTP, BTN_PROJ_FREEZE]
        }
        else
        {
            send_string dvProjector, "'~0080 1', $0D"
            on[dvTP, BTN_PROJ_FREEZE]
        }
    }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- BLANK TOGGLE                            *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_BLANK]
{
    push:
    {
        if ([dvTP, BTN_PROJ_BLANK])
        {
            send_string dvProjector, "'~0011 0', $0D"
            off[dvTP, BTN_PROJ_BLANK]
        }
        else
        {
            send_string dvProjector, "'~0011 1', $0D"
            on[dvTP, BTN_PROJ_BLANK]
        }
    }
}

(* --------------------------------------------------------*)
(* NAVIGATION                                              *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_NAV_HOME]
{
    push: { send_command dvTP, "'PAGE-Home'" }
}

button_event[dvTP, BTN_NAV_DISPLAY]
{
    push: { send_command dvTP, "'PAGE-Display'" }
}

button_event[dvTP, BTN_NAV_AUDIO]
{
    push: { send_command dvTP, "'PAGE-Audio'" }
}

button_event[dvTP, BTN_NAV_PRESETS]
{
    push: { send_command dvTP, "'PAGE-Presets'" }
}