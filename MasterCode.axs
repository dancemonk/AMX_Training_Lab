PROGRAM_NAME='MasterCode'
(***********************************************************)
(* KEY HISTORY:                                            *)
(* *)
(* v1.0 - Initial build                                    *)
(* v1.1 - Added heartbeat, confirmed feedback, retry logic *)
(* v1.2 - Fixed Optoma command format XX -> 00             *)
(* v1.3 - Fixed status query ~00124 1, response Ok0/Ok1    *)
(* v2.0 - Switched to RS-232 serial control                *)
(* v2.1 - Changed to RS-232 port 4                         *)
(* v2.2 - Multi-state feedback, button disable, status bar *)
(* v2.3 - Fixed state machine: consistent on[]/off[] + ANI *)
(* v2.4 - Code review pass                                 *)
(* v2.5 - Fixed State Bounce / Race Condition on Power     *)
(* Removed premature wait 30 / wait 50 polling.     *)
(* Restored sProjRxBuffer for safe string parsing.  *)
(* v2.6 - Fixed Disabled Gray Mask Glitch.                 *)
(* Changed ^ENA-21,0 to ^ENA-21,1 in all states to  *)
(* allow custom colors to show during transitions.  *)
(***********************************************************)

(***********************************************************)
(* DEVICE NUMBER DEFINITIONS                 *)
(***********************************************************)
DEFINE_DEVICE

// AMX MXT-1001 G5 Touch Panel
dvTP            = 10001:1:0

// Optoma EH415E Projector -- RS-232 -- NX-3200 Port 4
dvProjector     = 5001:4:0

(***********************************************************)
(* CONSTANT DEFINITIONS                     *)
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

(***********************************************************)
(* VARIABLE DEFINITIONS                     *)
(***********************************************************)
DEFINE_VARIABLE

volatile integer nSystemPower       // 0=off, 1=on
volatile integer nProjectorPower    // 0=off, 1=on
volatile integer nDebugMode         // 0=off (production), 1=on (diagnostics)

volatile long lHeartbeat[] = {30000}   // 30 second heartbeat

constant integer MAX_PROJ_RX_BUFFER = 100

// Buffer for parsing serial RS-232 messages safely
volatile char sProjRxBuffer[MAX_PROJ_RX_BUFFER]

(***********************************************************)
(* STARTUP CODE                        *)
(***********************************************************)
DEFINE_START

nDebugMode = 0  // Set to 1 only for on-site diagnostics
send_string 0, "'SYSTEM STARTED v2.6'"

// Configure RS-232 port 4
send_command dvProjector, "'SET BAUD 9600 N 8 1'"
send_command dvProjector, "'CLEAR_FAULT'"

// STATE: PROJECTOR OFF
// ON button  -> GRAY (State 1)
off[dvTP, BTN_PROJ_PWR_ON]
send_command dvTP, "'^ANI-20,1,1,0'"
send_command dvTP, "'^ENA-20,1'"

// OFF button -> RED (State 1) -- Guard variables prevent firing
off[dvTP, BTN_PROJ_PWR_OFF]
send_command dvTP, "'^ANI-21,1,1,0'"
send_command dvTP, "'^ENA-21,1'" // [cite: 302] Let native red color show

// HOME button -> GRAY (State 1)
off[dvTP, BTN_SYS_POWER_ON]
send_command dvTP, "'^ANI-1,1,1,0'"

// Disable all input and control buttons on boot
send_command dvTP, "'^ENA-22,0'"
send_command dvTP, "'^ENA-23,0'"
send_command dvTP, "'^ENA-24,0'"
send_command dvTP, "'^ENA-25,0'"
send_command dvTP, "'^ENA-26,0'"

// Status bar
send_command dvTP, "'^TXT-200,0,System OFF'"
send_command dvTP, "'^CFT-200,0,2,#E74C3C'"

// Start heartbeat -- polls projector every 30 seconds
timeline_create(1, lHeartbeat, 1, TIMELINE_RELATIVE, TIMELINE_REPEAT)

(***********************************************************)
(* EVENT HANDLERS                      *)
(***********************************************************)
DEFINE_EVENT

(* --------------------------------------------------------*)
(* HEARTBEAT -- POLL PROJECTOR STATE EVERY 30s             *)
(* --------------------------------------------------------*)
timeline_event[1]
{
    send_string dvProjector, "'~00124 1', $0D"
    if (nDebugMode) { send_string 0, "'Heartbeat - status query sent'" }
}

(* --------------------------------------------------------*)
(* PROJECTOR -- RS-232 DATA EVENT                          *)
(* --------------------------------------------------------*)
data_event[dvProjector]
{
    online:
    {
        send_command dvProjector, "'SET BAUD 9600 N 8 1'"
        send_command dvProjector, "'CLEAR_FAULT'"
        if (nDebugMode) { send_string 0, "'dvProjector ONLINE -- RS-232 re-initialized'" }
        wait 10 { send_string dvProjector, "'~00124 1', $0D" }
    }

    string:
    {
        if (nDebugMode) { send_string 0, "'RAW: [', data.text, ']'" }
        
        // Append raw data into our parsing buffer (with overflow guard)
        if (length_string(sProjRxBuffer) + length_string(data.text) <= MAX_PROJ_RX_BUFFER)
        {
            sProjRxBuffer = "sProjRxBuffer, data.text"
        }
        else
        {
            send_string 0, "'WARNING: RX buffer overflow -- flushing'"
            sProjRxBuffer = ''
        }
        
        // Loop through buffer to catch EVERY response separated by Carriage Return ($0D)
        while (find_string(sProjRxBuffer, "$0D", 1))
        {
            STACK_VAR char sCurrentMessage[50]
            sCurrentMessage = remove_string(sProjRxBuffer, "$0D", 1)

            // --- PROJECTOR ON ---
            if (find_string(sCurrentMessage, 'Ok1', 1))
            {
                nProjectorPower = 1
                nSystemPower    = 1

                // ON button  -> GREEN (State 3)
                on[dvTP, BTN_PROJ_PWR_ON]
                send_command dvTP, "'^ANI-20,3,3,0'"
                send_command dvTP, "'^ENA-20,1'"

                // OFF button -> GRAY (State 3) 
                off[dvTP, BTN_PROJ_PWR_OFF]
                send_command dvTP, "'^ANI-21,3,3,0'"
                send_command dvTP, "'^ENA-21,1'"

                // HOME button -> GREEN (State 3)
                on[dvTP, BTN_SYS_POWER_ON]
                send_command dvTP, "'^ANI-1,3,3,0'"

                // Enable input and control buttons
                send_command dvTP, "'^ENA-22,1'"
                send_command dvTP, "'^ENA-23,1'"
                send_command dvTP, "'^ENA-24,1'"
                send_command dvTP, "'^ENA-25,1'"
                send_command dvTP, "'^ENA-26,1'"

                send_command dvTP, "'^TXT-200,0,Projector ON'"
                send_command dvTP, "'^CFT-200,0,2,#2ECC71'"
                if (nDebugMode) { send_string 0, "'Projector confirmed: ON'" }
            }

            // --- PROJECTOR OFF ---
            else if (find_string(sCurrentMessage, 'Ok0', 1))
            {
                nProjectorPower = 0
                nSystemPower    = 0

                // ON button  -> GRAY (State 1)
                off[dvTP, BTN_PROJ_PWR_ON]
                send_command dvTP, "'^ANI-20,1,1,0'"
                send_command dvTP, "'^ENA-20,1'"

                // OFF button -> RED (State 1)
                off[dvTP, BTN_PROJ_PWR_OFF]
                send_command dvTP, "'^ANI-21,1,1,0'"
                send_command dvTP, "'^ENA-21,1'" // [cite: 302] Let native red color show

                // HOME button -> GRAY (State 1)
                off[dvTP, BTN_SYS_POWER_ON]
                send_command dvTP, "'^ANI-1,1,1,0'"

                // Disable input and control buttons
                send_command dvTP, "'^ENA-22,0'"
                send_command dvTP, "'^ENA-23,0'"
                send_command dvTP, "'^ENA-24,0'"
                send_command dvTP, "'^ENA-25,0'"
                send_command dvTP, "'^ENA-26,0'"

                send_command dvTP, "'^TXT-200,0,System OFF'"
                send_command dvTP, "'^CFT-200,0,2,#E74C3C'"
                if (nDebugMode) { send_string 0, "'Projector confirmed: OFF'" }
            }

            // --- WARMING UP ---
            else if (find_string(sCurrentMessage, 'INFO1', 1))
            {
                // ON button  -> AMBER (State 2)
                on[dvTP, BTN_PROJ_PWR_ON]
                send_command dvTP, "'^ANI-20,2,2,0'"
                send_command dvTP, "'^ENA-20,1'" // [cite: 302] Let amber color show

                // OFF button -> GRAY (State 3) 
                off[dvTP, BTN_PROJ_PWR_OFF]
                send_command dvTP, "'^ANI-21,3,3,0'"
                send_command dvTP, "'^ENA-21,1'" // [cite: 302] Guard variables prevent push

                // HOME button -> AMBER (State 2)
                on[dvTP, BTN_SYS_POWER_ON]
                send_command dvTP, "'^ANI-1,2,2,0'"

                // Disable input and control buttons
                send_command dvTP, "'^ENA-22,0'"
                send_command dvTP, "'^ENA-23,0'"
                send_command dvTP, "'^ENA-24,0'"
                send_command dvTP, "'^ENA-25,0'"
                send_command dvTP, "'^ENA-26,0'"

                send_command dvTP, "'^TXT-200,0,Projector Warming Up'"
                send_command dvTP, "'^CFT-200,0,2,#F39C12'"
                if (nDebugMode) { send_string 0, "'INFO1 received -- projector warming up'" }
            }

            // --- COOLING DOWN ---
            else if (find_string(sCurrentMessage, 'INFO2', 1))
            {
                // ON button  -> GRAY (State 1)
                off[dvTP, BTN_PROJ_PWR_ON]
                send_command dvTP, "'^ANI-20,1,1,0'"
                send_command dvTP, "'^ENA-20,1'"

                // OFF button -> DIMMED GREEN (State 2) 
                on[dvTP, BTN_PROJ_PWR_OFF]
                send_command dvTP, "'^ANI-21,2,2,0'"
                send_command dvTP, "'^ENA-21,1'" // [cite: 302] Let dim green color show

                // HOME button -> AMBER (State 2)
                on[dvTP, BTN_SYS_POWER_ON]
                send_command dvTP, "'^ANI-1,2,2,0'"

                // Disable input and control buttons
                send_command dvTP, "'^ENA-22,0'"
                send_command dvTP, "'^ENA-23,0'"
                send_command dvTP, "'^ENA-24,0'"
                send_command dvTP, "'^ENA-25,0'"
                send_command dvTP, "'^ENA-26,0'"

                send_command dvTP, "'^TXT-200,0,Projector Cooling Down'"
                send_command dvTP, "'^CFT-200,0,2,#F39C12'"
                if (nDebugMode) { send_string 0, "'Projector cooling down (INFO2)'" }
            }

            // --- COMMAND ACCEPTED (P ACK) ---
            else if (find_string(sCurrentMessage, 'P', 1))
            {
                if (nDebugMode) { send_string 0, "'Command accepted (P)'" }
            }
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
            // TURN ON -- show WARMING state immediately
            send_string dvProjector, "'~0000 1', $0D"

            // ON button  -> AMBER (State 2)
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,2,2,0'"
            send_command dvTP, "'^ENA-20,1'" // [cite: 303]

            // OFF button -> GRAY (State 3) 
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,3,3,0'"
            send_command dvTP, "'^ENA-21,1'" // [cite: 303]

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input and control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Starting...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nSystemPower    = 1
            nProjectorPower = 1
        }
        else
        {
            // TURN OFF -- show COOLING state immediately
            send_string dvProjector, "'~0000 0', $0D"

            // ON button  -> GRAY (State 1)
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,1,1,0'"
            send_command dvTP, "'^ENA-20,1'" // [cite: 303]

            // OFF button -> DIMMED GREEN (State 2) 
            on[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,2,2,0'"
            send_command dvTP, "'^ENA-21,1'" // [cite: 303]

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input and control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Shutting Down...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nSystemPower    = 0
            nProjectorPower = 0
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
            send_string dvProjector, "'~0000 1', $0D"

            // ON button  -> AMBER (State 2)
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,2,2,0'"
            send_command dvTP, "'^ENA-20,1'" // [cite: 303]

            // OFF button -> GRAY (State 3)
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,3,3,0'"
            send_command dvTP, "'^ENA-21,1'" // [cite: 303]

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input and control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Starting...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nProjectorPower = 1
            nSystemPower    = 1
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
            send_string dvProjector, "'~0000 0', $0D"

            // ON button  -> GRAY (State 1)
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,1,1,0'"
            send_command dvTP, "'^ENA-20,1'" // [cite: 303]

            // OFF button -> DIMMED GREEN (State 2) 
            on[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-21,2,2,0'"
            send_command dvTP, "'^ENA-21,1'" // [cite: 303]

            // HOME button -> AMBER (State 2)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,2,2,0'"

            // Disable input and control buttons
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"

            send_command dvTP, "'^TXT-200,0,Projector Shutting Down...'"
            send_command dvTP, "'^CFT-200,0,2,#F39C12'"

            nProjectorPower = 0
            nSystemPower    = 0
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