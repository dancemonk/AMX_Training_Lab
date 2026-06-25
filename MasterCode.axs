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
(*        Removed premature wait 30 / wait 50 polling.     *)
(*        Restored sProjRxBuffer for safe string parsing.  *)
(* v2.6 - Fixed Disabled Gray Mask Glitch.                 *)
(*        Changed ^ENA-21,0 to ^ENA-21,1 in all states to  *)
(*        allow custom colors to show during transitions.  *)
(* v3.0 - Refactored duplicate UI patterns into shared     *)
(*        utility functions.                               *)
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

(* --------------------------------------------------------*)
(* PROJECTOR UI STATES                                     *)
(* --------------------------------------------------------*)
PROJ_STATE_OFF          = 1
PROJ_STATE_WARMING      = 2
PROJ_STATE_ON           = 3
PROJ_STATE_COOLING      = 4

(***********************************************************)
(* VARIABLE DEFINITIONS                     *)
(***********************************************************)
DEFINE_VARIABLE

volatile integer nSystemPower       // 0=off, 1=on
volatile integer nProjectorPower    // 0=off, 1=on

volatile long lHeartbeat[] = {30000}   // 30 second heartbeat

// Buffer for parsing serial RS-232 messages safely
volatile char sProjRxBuffer[100]

(***********************************************************)
(* SHARED UTILITY FUNCTIONS                                *)
(***********************************************************)

(* --------------------------------------------------------*)
(* fnSetButtonFeedback                                     *)
(* Sets a button's channel feedback and animation state.   *)
(* --------------------------------------------------------*)
DEFINE_FUNCTION fnSetButtonFeedback(DEV dvPanel, INTEGER nButton, INTEGER nFeedbackOn, INTEGER nAniState)
{
    if (nFeedbackOn)
        on[dvPanel, nButton]
    else
        off[dvPanel, nButton]
    send_command dvPanel, "'^ANI-', itoa(nButton), ',', itoa(nAniState), ',', itoa(nAniState), ',0'"
    send_command dvPanel, "'^ENA-', itoa(nButton), ',1'"
}

(* --------------------------------------------------------*)
(* fnEnableInputButtons                                    *)
(* Enables (1) or disables (0) all input/control buttons.  *)
(* --------------------------------------------------------*)
DEFINE_FUNCTION fnEnableInputButtons(DEV dvPanel, INTEGER nEnable)
{
    send_command dvPanel, "'^ENA-22,', itoa(nEnable)"
    send_command dvPanel, "'^ENA-23,', itoa(nEnable)"
    send_command dvPanel, "'^ENA-24,', itoa(nEnable)"
    send_command dvPanel, "'^ENA-25,', itoa(nEnable)"
    send_command dvPanel, "'^ENA-26,', itoa(nEnable)"
}

(* --------------------------------------------------------*)
(* fnUpdateStatusBar                                       *)
(* Sets the status bar text and font color.                *)
(* --------------------------------------------------------*)
DEFINE_FUNCTION fnUpdateStatusBar(DEV dvPanel, CHAR sText[], CHAR sColor[])
{
    send_command dvPanel, "'^TXT-200,0,', sText"
    send_command dvPanel, "'^CFT-200,0,2,', sColor"
}

(* --------------------------------------------------------*)
(* fnSetProjectorUI                                        *)
(* Applies a complete projector UI state to the touch      *)
(* panel: power button feedback, input button enables,     *)
(* and status bar.                                         *)
(* --------------------------------------------------------*)
DEFINE_FUNCTION fnSetProjectorUI(INTEGER nState, CHAR sStatusText[], CHAR sStatusColor[])
{
    switch (nState)
    {
        case PROJ_STATE_OFF:
        {
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_ON,  0, 1)
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_OFF, 0, 1)
            fnSetButtonFeedback(dvTP, BTN_SYS_POWER_ON, 0, 1)
            fnEnableInputButtons(dvTP, 0)
        }
        case PROJ_STATE_WARMING:
        {
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_ON,  1, 2)
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_OFF, 0, 3)
            fnSetButtonFeedback(dvTP, BTN_SYS_POWER_ON, 1, 2)
            fnEnableInputButtons(dvTP, 0)
        }
        case PROJ_STATE_ON:
        {
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_ON,  1, 3)
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_OFF, 0, 3)
            fnSetButtonFeedback(dvTP, BTN_SYS_POWER_ON, 1, 3)
            fnEnableInputButtons(dvTP, 1)
        }
        case PROJ_STATE_COOLING:
        {
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_ON,  0, 1)
            fnSetButtonFeedback(dvTP, BTN_PROJ_PWR_OFF, 1, 2)
            fnSetButtonFeedback(dvTP, BTN_SYS_POWER_ON, 1, 2)
            fnEnableInputButtons(dvTP, 0)
        }
    }
    fnUpdateStatusBar(dvTP, sStatusText, sStatusColor)
}

(* --------------------------------------------------------*)
(* fnSelectInput                                           *)
(* Sends the input-select command and applies mutual-      *)
(* exclusive feedback on the three input buttons.          *)
(* --------------------------------------------------------*)
DEFINE_FUNCTION fnSelectInput(CHAR sInputCmd[], INTEGER nActiveBtn)
{
    send_string dvProjector, "sInputCmd, $0D"
    [dvTP, BTN_INP_HDMI]  = (nActiveBtn == BTN_INP_HDMI)
    [dvTP, BTN_INP_VGA]   = (nActiveBtn == BTN_INP_VGA)
    [dvTP, BTN_INP_HDMI2] = (nActiveBtn == BTN_INP_HDMI2)
}

(* --------------------------------------------------------*)
(* fnToggleFeature                                         *)
(* Toggles a projector feature (freeze / blank) and        *)
(* updates button feedback.                                *)
(* --------------------------------------------------------*)
DEFINE_FUNCTION fnToggleFeature(INTEGER nButton, CHAR sOnCmd[], CHAR sOffCmd[])
{
    if ([dvTP, nButton])
    {
        send_string dvProjector, "sOffCmd, $0D"
        off[dvTP, nButton]
    }
    else
    {
        send_string dvProjector, "sOnCmd, $0D"
        on[dvTP, nButton]
    }
}

(***********************************************************)
(* STARTUP CODE                        *)
(***********************************************************)
DEFINE_START

send_string 0, "'SYSTEM STARTED v3.0'"

// Configure RS-232 port 4
send_command dvProjector, "'SET BAUD 9600 N 8 1'"
send_command dvProjector, "'CLEAR_FAULT'"

fnSetProjectorUI(PROJ_STATE_OFF, 'System OFF', '#E74C3C')

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
    send_string 0, "'Heartbeat - status query sent'"
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
        send_string 0, "'dvProjector ONLINE -- RS-232 re-initialized'"
        wait 10 { send_string dvProjector, "'~00124 1', $0D" }
    }

    string:
    {
        send_string 0, "'RAW: [', data.text, ']'"
        
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
                fnSetProjectorUI(PROJ_STATE_ON, 'Projector ON', '#2ECC71')
                send_string 0, "'Projector confirmed: ON'"
            }

            // --- PROJECTOR OFF ---
            else if (find_string(sCurrentMessage, 'Ok0', 1))
            {
                nProjectorPower = 0
                nSystemPower    = 0
                fnSetProjectorUI(PROJ_STATE_OFF, 'System OFF', '#E74C3C')
                send_string 0, "'Projector confirmed: OFF'"
            }

            // --- WARMING UP ---
            else if (find_string(sCurrentMessage, 'INFO1', 1))
            {
                fnSetProjectorUI(PROJ_STATE_WARMING, 'Projector Warming Up', '#F39C12')
                send_string 0, "'INFO1 received -- projector warming up'"
            }

            // --- COOLING DOWN ---
            else if (find_string(sCurrentMessage, 'INFO2', 1))
            {
                fnSetProjectorUI(PROJ_STATE_COOLING, 'Projector Cooling Down', '#F39C12')
                send_string 0, "'Projector cooling down (INFO2)'"
            }

            // --- COMMAND ACCEPTED (P ACK) ---
            else if (find_string(sCurrentMessage, 'P', 1))
            {
                send_string 0, "'Command accepted (P)'"
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
            send_string dvProjector, "'~0000 1', $0D"
            fnSetProjectorUI(PROJ_STATE_WARMING, 'Projector Starting...', '#F39C12')
            nSystemPower    = 1
            nProjectorPower = 1
        }
        else
        {
            send_string dvProjector, "'~0000 0', $0D"
            fnSetProjectorUI(PROJ_STATE_COOLING, 'Projector Shutting Down...', '#F39C12')
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
            fnSetProjectorUI(PROJ_STATE_WARMING, 'Projector Starting...', '#F39C12')
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
            fnSetProjectorUI(PROJ_STATE_COOLING, 'Projector Shutting Down...', '#F39C12')
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
    push: { fnSelectInput("'~0012 5'", BTN_INP_HDMI) }
}

button_event[dvTP, BTN_INP_VGA]
{
    push: { fnSelectInput("'~0012 1'", BTN_INP_VGA) }
}

button_event[dvTP, BTN_INP_HDMI2]
{
    push: { fnSelectInput("'~0012 6'", BTN_INP_HDMI2) }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- FREEZE TOGGLE                           *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_FREEZE]
{
    push: { fnToggleFeature(BTN_PROJ_FREEZE, "'~0080 1'", "'~0080 0'") }
}

(* --------------------------------------------------------*)
(* DISPLAY PAGE -- BLANK TOGGLE                            *)
(* --------------------------------------------------------*)
button_event[dvTP, BTN_PROJ_BLANK]
{
    push: { fnToggleFeature(BTN_PROJ_BLANK, "'~0011 1'", "'~0011 0'") }
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
