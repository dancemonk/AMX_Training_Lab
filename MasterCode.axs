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
(*         Changed ^ENA-21,0 to ^ENA-21,1 in all states to  *)
(*         allow custom colors to show during transitions.  *)
(* v2.7 - Improved error handling:                         *)
(*         Added offline/onerror events for RS-232 port.   *)
(*         Added comm timeout detection (3 missed polls).  *)
(*         Added buffer overflow guard with flush.         *)
(*         Added F (NACK) and unrecognized response handling.*)
(*         Added power/comm-fault guards on input/controls.*)
(*         Added touch panel online/offline with UI re-sync.*)
(***********************************************************)

(***********************************************************)
(* DEVICE NUMBER DEFINITIONS                 *)
(***********************************************************)
DEFINE_DEVICE

// AMX MXT-1001 G5 Touch Panel -- 192.168.21.12
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

volatile long lHeartbeat[] = {30000}   // 30 second heartbeat
volatile long lCommTimeout[] = {5000}  // 5 second comm timeout

// Buffer for parsing serial RS-232 messages safely
volatile char sProjRxBuffer[100]

// Communication state tracking
volatile integer nCommFault         // 1=comm fault active
volatile integer nAwaitingResponse  // 1=waiting for projector reply
volatile integer nHeartbeatMisses   // consecutive missed heartbeats

(***********************************************************)
(* STARTUP CODE                        *)
(***********************************************************)
DEFINE_START

send_string 0, "'SYSTEM STARTED v2.7'"

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

// Comm timeout timeline -- detects missing responses
timeline_create(2, lCommTimeout, 1, TIMELINE_RELATIVE, TIMELINE_REPEAT)

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
    nAwaitingResponse = 1
    timeline_set(2, 0)  // Reset comm timeout countdown
    send_string 0, "'Heartbeat - status query sent'"
}

(* --------------------------------------------------------*)
(* COMM TIMEOUT -- NO RESPONSE FROM PROJECTOR              *)
(* --------------------------------------------------------*)
timeline_event[2]
{
    if (nAwaitingResponse)
    {
        nHeartbeatMisses = nHeartbeatMisses + 1
        send_string 0, "'WARNING: Projector did not respond (miss #', itoa(nHeartbeatMisses), ')'"

        if (nHeartbeatMisses >= 3)
        {
            nCommFault = 1
            send_command dvTP, "'^TXT-200,0,COMM FAULT - No Response'"
            send_command dvTP, "'^CFT-200,0,2,#9B59B6'"
            send_string 0, "'ERROR: Comm fault -- projector unresponsive after 3 missed heartbeats'"
        }
    }
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
        nCommFault = 0
        nHeartbeatMisses = 0
        send_string 0, "'dvProjector ONLINE -- RS-232 re-initialized'"
        wait 10 { send_string dvProjector, "'~00124 1', $0D" }
    }

    offline:
    {
        nCommFault = 1
        nHeartbeatMisses = 0
        send_string 0, "'ERROR: dvProjector OFFLINE -- RS-232 port lost'"
        send_command dvTP, "'^TXT-200,0,COMM FAULT - Port Offline'"
        send_command dvTP, "'^CFT-200,0,2,#9B59B6'"
    }

    onerror:
    {
        nCommFault = 1
        send_string 0, "'ERROR: dvProjector RS-232 fault [', data.text, ']'"
        send_command dvTP, "'^TXT-200,0,COMM ERROR'"
        send_command dvTP, "'^CFT-200,0,2,#9B59B6'"
        send_command dvProjector, "'CLEAR_FAULT'"
    }

    string:
    {
        send_string 0, "'RAW: [', data.text, ']'"

        // Clear comm fault on any valid data received
        nAwaitingResponse = 0
        nHeartbeatMisses = 0
        if (nCommFault)
        {
            nCommFault = 0
            send_string 0, "'Comm fault cleared -- data received'"
        }

        // Guard against buffer overflow
        if (length_string(sProjRxBuffer) + length_string(data.text) > 100)
        {
            send_string 0, "'WARNING: RX buffer overflow -- flushing'"
            sProjRxBuffer = ''
        }

        // Append raw data into our parsing buffer
        sProjRxBuffer = "sProjRxBuffer, data.text"
        
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
                send_string 0, "'Projector confirmed: ON'"
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
                send_string 0, "'Projector confirmed: OFF'"
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
                send_string 0, "'INFO1 received -- projector warming up'"
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
                send_string 0, "'Projector cooling down (INFO2)'"
            }

            // --- COMMAND ACCEPTED (P ACK) ---
            else if (find_string(sCurrentMessage, 'P', 1))
            {
                send_string 0, "'Command accepted (P)'"
            }

            // --- COMMAND FAILED (F NACK) ---
            else if (find_string(sCurrentMessage, 'F', 1))
            {
                send_string 0, "'ERROR: Command REJECTED by projector (F)'"
                send_command dvTP, "'^TXT-200,0,Command Failed'"
                send_command dvTP, "'^CFT-200,0,2,#E74C3C'"
                // Re-query actual state after failed command
                wait 10 { send_string dvProjector, "'~00124 1', $0D" }
            }

            // --- UNRECOGNIZED RESPONSE ---
            else if (length_string(sCurrentMessage) > 1)
            {
                send_string 0, "'WARNING: Unrecognized response [', sCurrentMessage, ']'"
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
        if (nProjectorPower == 1 && nCommFault == 0)
        {
            send_string dvProjector, "'~0012 5', $0D"
            on[dvTP,  BTN_INP_HDMI]
            off[dvTP, BTN_INP_VGA]
            off[dvTP, BTN_INP_HDMI2]
        }
        else
        {
            send_string 0, "'INPUT HDMI1 ignored -- projector not ready or comm fault'"
        }
    }
}

button_event[dvTP, BTN_INP_VGA]
{
    push:
    {
        if (nProjectorPower == 1 && nCommFault == 0)
        {
            send_string dvProjector, "'~0012 1', $0D"
            off[dvTP, BTN_INP_HDMI]
            on[dvTP,  BTN_INP_VGA]
            off[dvTP, BTN_INP_HDMI2]
        }
        else
        {
            send_string 0, "'INPUT VGA ignored -- projector not ready or comm fault'"
        }
    }
}

button_event[dvTP, BTN_INP_HDMI2]
{
    push:
    {
        if (nProjectorPower == 1 && nCommFault == 0)
        {
            send_string dvProjector, "'~0012 6', $0D"
            off[dvTP, BTN_INP_HDMI]
            off[dvTP, BTN_INP_VGA]
            on[dvTP,  BTN_INP_HDMI2]
        }
        else
        {
            send_string 0, "'INPUT HDMI2 ignored -- projector not ready or comm fault'"
        }
    }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- FREEZE TOGGLE                           *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_FREEZE]
{
    push:
    {
        if (nProjectorPower == 0 || nCommFault)
        {
            send_string 0, "'FREEZE ignored -- projector not ready or comm fault'"
            return
        }

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
        if (nProjectorPower == 0 || nCommFault)
        {
            send_string 0, "'BLANK ignored -- projector not ready or comm fault'"
            return
        }

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
(* TOUCH PANEL -- ONLINE / OFFLINE                         *)
(* --------------------------------------------------------*)
data_event[dvTP]
{
    online:
    {
        send_string 0, "'dvTP ONLINE -- touch panel connected'"
        // Re-sync UI state on panel reconnect
        if (nProjectorPower)
        {
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,3,3,0'"
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,3,3,0'"
            send_command dvTP, "'^ENA-22,1'"
            send_command dvTP, "'^ENA-23,1'"
            send_command dvTP, "'^ENA-24,1'"
            send_command dvTP, "'^ENA-25,1'"
            send_command dvTP, "'^ENA-26,1'"
            send_command dvTP, "'^TXT-200,0,Projector ON'"
            send_command dvTP, "'^CFT-200,0,2,#2ECC71'"
        }
        else
        {
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-20,1,1,0'"
            off[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-1,1,1,0'"
            send_command dvTP, "'^ENA-22,0'"
            send_command dvTP, "'^ENA-23,0'"
            send_command dvTP, "'^ENA-24,0'"
            send_command dvTP, "'^ENA-25,0'"
            send_command dvTP, "'^ENA-26,0'"
            send_command dvTP, "'^TXT-200,0,System OFF'"
            send_command dvTP, "'^CFT-200,0,2,#E74C3C'"
        }

        if (nCommFault)
        {
            send_command dvTP, "'^TXT-200,0,COMM FAULT - No Response'"
            send_command dvTP, "'^CFT-200,0,2,#9B59B6'"
        }
    }

    offline:
    {
        send_string 0, "'WARNING: dvTP OFFLINE -- touch panel disconnected'"
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