PROGRAM_NAME='MasterCode'
(***********************************************************)
(* KEY HISTORY:                                            *)
(* v2.9  - BUG FIX PASS (Buffer, Variables, Constants).     *)
(* v2.10 - RESTORED 3-STATE POWER LOGIC. Power buttons maps *)
(* back to dedicated 3-state tracking loops.       *)
(* v2.11 - FIXED NAVIGATION SELECTION BOUNCE. Combined     *)
(* explicit on[]/off[] channel states with ^ANI     *)
(* to ensure 2-state navigation buttons stay        *)
(* latched in their active states on the panel.    *)
(***********************************************************)

(***********************************************************)
(* DEVICE NUMBER DEFINITIONS                               *)
(***********************************************************)
DEFINE_DEVICE

// AMX MXT-1001 G5 Touch Panel -- 192.168.21.12
dvTP            = 10001:1:0

// Optoma EH415E Projector -- RS-232 -- NX-3200 Port 4
dvProjector     = 5001:4:0

(***********************************************************)
(* CONSTANT DEFINITIONS                                    *)
(***********************************************************)
DEFINE_CONSTANT

// TOUCH PANEL -- HOME PAGE
BTN_SYS_POWER_ON        = 1

// TOUCH PANEL -- DISPLAY PAGE
BTN_PROJ_PWR_ON         = 20
BTN_PROJ_PWR_OFF        = 21
BTN_INP_HDMI            = 22
BTN_INP_VGA             = 23
BTN_INP_HDMI2           = 24
BTN_PROJ_FREEZE         = 25
BTN_PROJ_BLANK          = 26

// TOUCH PANEL -- NAVIGATION
BTN_NAV_HOME            = 101
BTN_NAV_DISPLAY         = 102
BTN_NAV_AUDIO           = 103
BTN_NAV_PRESETS         = 104

// STATUS BAR
TXT_STATUS              = 200

(***********************************************************)
(* VARIABLE DEFINITIONS                                    *)
(***********************************************************)
DEFINE_VARIABLE

volatile integer nSystemPower       // 0=off, 1=on
volatile integer nProjectorPower    // 0=off, 1=on
volatile integer nProjectorFreeze   // 0=unfrozen, 1=frozen
volatile integer nProjectorBlank    // 0=unblanked, 1=blanked

volatile long lHeartbeat[] = {30000}   // 30 second heartbeat
volatile char sProjRxBuffer[255]       // Serial buffer

(***********************************************************)
(* STARTUP CODE                                            *)
(***********************************************************)
DEFINE_START

send_string 0, "'SYSTEM STARTED v2.11'"

// Configure RS-232 port 4
send_command dvProjector, "'SET BAUD 9600 N 8 1'"
send_command dvProjector, "'CLEAR_FAULT'"

// INITIALIZE UI STATES TO "OFF" (State 1)

// ON Button -> State 1 (GRAY)
off[dvTP, BTN_PROJ_PWR_ON]
send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_ON), ',1,1,0'"
send_command dvTP, "'^ENA-', itoa(BTN_PROJ_PWR_ON), ',1'"

// OFF Button -> State 1 (RED)
off[dvTP, BTN_PROJ_PWR_OFF]
send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_OFF), ',1,1,0'"
send_command dvTP, "'^ENA-', itoa(BTN_PROJ_PWR_OFF), ',1'"

// SYS Button -> State 1 (GRAY)
off[dvTP, BTN_SYS_POWER_ON]
send_command dvTP, "'^ANI-', itoa(BTN_SYS_POWER_ON), ',1,1,0'"

// Navigation Bar Initialization - Force HOME to active channel and active graphic
on[dvTP, BTN_NAV_HOME]
send_command dvTP, "'^ANI-', itoa(BTN_NAV_HOME), ',2,2,0'"

off[dvTP, BTN_NAV_DISPLAY]
send_command dvTP, "'^ANI-', itoa(BTN_NAV_DISPLAY), ',1,1,0'"

off[dvTP, BTN_NAV_AUDIO]
send_command dvTP, "'^ANI-', itoa(BTN_NAV_AUDIO), ',1,1,0'"

off[dvTP, BTN_NAV_PRESETS]
send_command dvTP, "'^ANI-', itoa(BTN_NAV_PRESETS), ',1,1,0'"

// Disable inputs and controls until system is ON
send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI), ',0'"
send_command dvTP, "'^ENA-', itoa(BTN_INP_VGA), ',0'"
send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI2), ',0'"
send_command dvTP, "'^ENA-', itoa(BTN_PROJ_FREEZE), ',0'"
send_command dvTP, "'^ENA-', itoa(BTN_PROJ_BLANK), ',0'"

send_command dvTP, "'^TXT-', itoa(TXT_STATUS), ',0,System OFF'"
send_command dvTP, "'^CFT-', itoa(TXT_STATUS), ',0,2,#E74C3C'"

timeline_create(1, lHeartbeat, 1, TIMELINE_RELATIVE, TIMELINE_REPEAT)

(***********************************************************)
(* EVENT HANDLERS                                          *)
(***********************************************************)
DEFINE_EVENT

timeline_event[1]
{
    send_string dvProjector, "'~00124 1', $0D"
}

data_event[dvProjector]
{
    online:
    {
        send_command dvProjector, "'SET BAUD 9600 N 8 1'"
        send_command dvProjector, "'CLEAR_FAULT'"
        wait 10 { send_string dvProjector, "'~00124 1', $0D" }
    }

    string:
    {
        sProjRxBuffer = "sProjRxBuffer, data.text"
        
        while (find_string(sProjRxBuffer, "$0D", 1))
        {
            STACK_VAR char sCurrentMessage[50]
            sCurrentMessage = remove_string(sProjRxBuffer, "$0D", 1)

            // HARDWARE CONFIRMATION
            if (find_string(sCurrentMessage, 'Ok1', 1))
            {
                nProjectorPower = 1
                nSystemPower    = 1
                
                // Keep states locked in State 3
                on[dvTP, BTN_PROJ_PWR_ON]
                send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_ON), ',3,3,0'"
                off[dvTP, BTN_PROJ_PWR_OFF]
                send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_OFF), ',3,3,0'"
                on[dvTP, BTN_SYS_POWER_ON]
                send_command dvTP, "'^ANI-', itoa(BTN_SYS_POWER_ON), ',3,3,0'"
                
                send_command dvTP, "'^TXT-', itoa(TXT_STATUS), ',0,System Active'"
                send_command dvTP, "'^CFT-', itoa(TXT_STATUS), ',0,2,#2ECC71'"
            }
            else if (find_string(sCurrentMessage, 'Ok0', 1))
            {
                nProjectorPower = 0
                nSystemPower    = 0
                
                // Keep states locked in State 1
                off[dvTP, BTN_PROJ_PWR_ON]
                send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_ON), ',1,1,0'"
                off[dvTP, BTN_PROJ_PWR_OFF]
                send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_OFF), ',1,1,0'"
                off[dvTP, BTN_SYS_POWER_ON]
                send_command dvTP, "'^ANI-', itoa(BTN_SYS_POWER_ON), ',1,1,0'"
                
                send_command dvTP, "'^TXT-', itoa(TXT_STATUS), ',0,System OFF'"
                send_command dvTP, "'^CFT-', itoa(TXT_STATUS), ',0,2,#E74C3C'"
            }
        }
    }
}

(* --------------------------------------------------------*)
(* SYSTEM POWER TOGGLE                                     *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_SYS_POWER_ON]
{
    push:
    {
        if (nSystemPower == 0)
        {
            send_string dvProjector, "'~0000 1', $0D"
            nSystemPower = 1
            nProjectorPower = 1

            // Show WARMING (State 2 - Amber/Gray Layout)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_SYS_POWER_ON), ',2,2,0'"
            
            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_ON), ',2,2,0'"
            
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_OFF), ',3,3,0'"

            // Unlock inputs
            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_VGA), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI2), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_FREEZE), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_BLANK), ',1'"
            
            send_command dvTP, "'^TXT-', itoa(TXT_STATUS), ',0,Starting Up...'"
            send_command dvTP, "'^CFT-', itoa(TXT_STATUS), ',0,2,#F39C12'"
        }
        else
        {
            send_string dvProjector, "'~0000 0', $0D"
            nSystemPower = 0
            nProjectorPower = 0
            
            nProjectorFreeze = 0
            nProjectorBlank = 0
            off[dvTP, BTN_PROJ_FREEZE]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_FREEZE), ',1,1,0'"
            off[dvTP, BTN_PROJ_BLANK]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_BLANK), ',1,1,0'"

            // Show COOLING (State 2 - Amber/DimGreen Layout)
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_SYS_POWER_ON), ',2,2,0'"

            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_ON), ',1,1,0'"
            
            on[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_OFF), ',2,2,0'"

            // Lock inputs
            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_VGA), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI2), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_FREEZE), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_BLANK), ',0'"
            
            send_command dvTP, "'^TXT-', itoa(TXT_STATUS), ',0,Cooling Down...'"
            send_command dvTP, "'^CFT-', itoa(TXT_STATUS), ',0,2,#F39C12'"
        }
    }
}

(* --------------------------------------------------------*)
(* DISCRETE POWER ON / OFF                                 *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_PWR_ON]
{
    push:
    {
        if (nProjectorPower == 0)
        {
            send_string dvProjector, "'~0000 1', $0D"
            nProjectorPower = 1
            nSystemPower = 1

            on[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_ON), ',2,2,0'"
            
            off[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_OFF), ',3,3,0'"
            
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_SYS_POWER_ON), ',2,2,0'"

            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_VGA), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI2), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_FREEZE), ',1'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_BLANK), ',1'"
            
            send_command dvTP, "'^TXT-', itoa(TXT_STATUS), ',0,Starting Up...'"
            send_command dvTP, "'^CFT-', itoa(TXT_STATUS), ',0,2,#F39C12'"
        }
    }
}

button_event[dvTP, BTN_PROJ_PWR_OFF]
{
    push:
    {
        if (nProjectorPower == 1)
        {
            send_string dvProjector, "'~0000 0', $0D"
            nProjectorPower = 0
            nSystemPower = 0
            
            nProjectorFreeze = 0
            nProjectorBlank = 0
            off[dvTP, BTN_PROJ_FREEZE]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_FREEZE), ',1,1,0'"
            off[dvTP, BTN_PROJ_BLANK]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_BLANK), ',1,1,0'"

            on[dvTP, BTN_PROJ_PWR_OFF]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_OFF), ',2,2,0'"
            
            off[dvTP, BTN_PROJ_PWR_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_PWR_ON), ',1,1,0'"
            
            on[dvTP, BTN_SYS_POWER_ON]
            send_command dvTP, "'^ANI-', itoa(BTN_SYS_POWER_ON), ',2,2,0'"

            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_VGA), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_INP_HDMI2), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_FREEZE), ',0'"
            send_command dvTP, "'^ENA-', itoa(BTN_PROJ_BLANK), ',0'"
            
            send_command dvTP, "'^TXT-', itoa(TXT_STATUS), ',0,Cooling Down...'"
            send_command dvTP, "'^CFT-', itoa(TXT_STATUS), ',0,2,#F39C12'"
        }
    }
}

(* --------------------------------------------------------*)
(* INPUT SELECTION - RADIO BUTTON LOGIC                    *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_INP_HDMI]
{
    push:
    {
        send_string dvProjector, "'~0012 5', $0D"
        
        on[dvTP, BTN_INP_HDMI]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_HDMI), ',2,2,0'"
        
        off[dvTP, BTN_INP_VGA]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_VGA), ',1,1,0'"
        off[dvTP, BTN_INP_HDMI2]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_HDMI2), ',1,1,0'"
    }
}

button_event[dvTP, BTN_INP_VGA]
{
    push:
    {
        send_string dvProjector, "'~0012 1', $0D"
        
        off[dvTP, BTN_INP_HDMI]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_HDMI), ',1,1,0'"
        
        on[dvTP, BTN_INP_VGA]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_VGA), ',2,2,0'"
        
        off[dvTP, BTN_INP_HDMI2]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_HDMI2), ',1,1,0'"
    }
}

button_event[dvTP, BTN_INP_HDMI2]
{
    push:
    {
        send_string dvProjector, "'~0012 6', $0D"
        
        off[dvTP, BTN_INP_HDMI]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_HDMI), ',1,1,0'"
        off[dvTP, BTN_INP_VGA]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_VGA), ',1,1,0'"
        
        on[dvTP, BTN_INP_HDMI2]
        send_command dvTP, "'^ANI-', itoa(BTN_INP_HDMI2), ',2,2,0'"
    }
}

(* --------------------------------------------------------*)
(* DISPLAY CONTROLS - SAFE VARIABLE TOGGLE LOGIC           *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_FREEZE]
{
    push:
    {
        if (nProjectorFreeze == 1)
        {
            send_string dvProjector, "'~0080 0', $0D"
            nProjectorFreeze = 0
            off[dvTP, BTN_PROJ_FREEZE]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_FREEZE), ',1,1,0'"
        }
        else
        {
            send_string dvProjector, "'~0080 1', $0D"
            nProjectorFreeze = 1
            on[dvTP, BTN_PROJ_FREEZE]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_FREEZE), ',2,2,0'"
        }
    }
}

button_event[dvTP, BTN_PROJ_BLANK]
{
    push:
    {
        if (nProjectorBlank == 1)
        {
            send_string dvProjector, "'~0011 0', $0D"
            nProjectorBlank = 0
            off[dvTP, BTN_PROJ_BLANK]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_BLANK), ',1,1,0'"
        }
        else
        {
            send_string dvProjector, "'~0011 1', $0D"
            nProjectorBlank = 1
            on[dvTP, BTN_PROJ_BLANK]
            send_command dvTP, "'^ANI-', itoa(BTN_PROJ_BLANK), ',2,2,0'"
        }
    }
}

(* --------------------------------------------------------*)
(* NAVIGATION TABS - INTERLOCKING LATCH LOGIC              *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_NAV_HOME]
{
    push: 
    { 
        send_command dvTP, "'PAGE-Home'" 
        
        // Sync Channel States to latch color
        on[dvTP, BTN_NAV_HOME]
        off[dvTP, BTN_NAV_DISPLAY]
        off[dvTP, BTN_NAV_AUDIO]
        off[dvTP, BTN_NAV_PRESETS]
        
        // Force Graphic State engine overrides
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_HOME), ',2,2,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_DISPLAY), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_AUDIO), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_PRESETS), ',1,1,0'"
    }
}

button_event[dvTP, BTN_NAV_DISPLAY]
{
    push: 
    { 
        send_command dvTP, "'PAGE-Display'" 
        
        // Sync Channel States to latch color
        off[dvTP, BTN_NAV_HOME]
        on[dvTP, BTN_NAV_DISPLAY]
        off[dvTP, BTN_NAV_AUDIO]
        off[dvTP, BTN_NAV_PRESETS]
        
        // Force Graphic State engine overrides
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_HOME), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_DISPLAY), ',2,2,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_AUDIO), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_PRESETS), ',1,1,0'"
    }
}

button_event[dvTP, BTN_NAV_AUDIO]
{
    push: 
    { 
        send_command dvTP, "'PAGE-Audio'" 
        
        // Sync Channel States to latch color
        off[dvTP, BTN_NAV_HOME]
        off[dvTP, BTN_NAV_DISPLAY]
        on[dvTP, BTN_NAV_AUDIO]
        off[dvTP, BTN_NAV_PRESETS]
        
        // Force Graphic State engine overrides
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_HOME), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_DISPLAY), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_AUDIO), ',2,2,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_PRESETS), ',1,1,0'"
    }
}

button_event[dvTP, BTN_NAV_PRESETS]
{
    push: 
    { 
        send_command dvTP, "'PAGE-Presets'"
        
        // Sync Channel States to latch color
        off[dvTP, BTN_NAV_HOME]
        off[dvTP, BTN_NAV_DISPLAY]
        off[dvTP, BTN_NAV_AUDIO]
        on[dvTP, BTN_NAV_PRESETS]
        
        // Force Graphic State engine overrides
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_HOME), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_DISPLAY), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_AUDIO), ',1,1,0'"
        send_command dvTP, "'^ANI-', itoa(BTN_NAV_PRESETS), ',2,2,0'"
    }
}