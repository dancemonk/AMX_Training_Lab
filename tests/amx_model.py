"""
Python model of the MasterCode.axs AMX NetLinx control system.

This module mirrors the logic from MasterCode.axs so that the state machine,
serial response parsing, button guard conditions, input selection, and UI
feedback can be unit-tested without AMX hardware.
"""


# ---------------------------------------------------------------------------
# Constants (mirror DEFINE_CONSTANT in MasterCode.axs)
# ---------------------------------------------------------------------------
BTN_SYS_POWER_ON = 1
BTN_PROJ_PWR_ON = 20
BTN_PROJ_PWR_OFF = 21
BTN_INP_HDMI = 22
BTN_INP_VGA = 23
BTN_INP_HDMI2 = 24
BTN_PROJ_FREEZE = 25
BTN_PROJ_BLANK = 26
BTN_NAV_HOME = 101
BTN_NAV_DISPLAY = 102
BTN_NAV_AUDIO = 103
BTN_NAV_PRESETS = 104


# ---------------------------------------------------------------------------
# Projector power state enumeration
# ---------------------------------------------------------------------------
class ProjState:
    OFF = "off"
    WARMING = "warming"
    ON = "on"
    COOLING = "cooling"


# ---------------------------------------------------------------------------
# Button visual state
# ---------------------------------------------------------------------------
class ButtonState:
    """Mirrors the AMX ANI multi-state button states."""
    GRAY = 1
    AMBER = 2
    GREEN = 3
    RED = 1       # OFF button state 1 is red by design
    DIMMED_GREEN = 2  # OFF button state 2


# ---------------------------------------------------------------------------
# RS-232 Command constants
# ---------------------------------------------------------------------------
CMD_POWER_ON = "~0000 1\r"
CMD_POWER_OFF = "~0000 0\r"
CMD_STATUS_QUERY = "~00124 1\r"
CMD_INPUT_HDMI = "~0012 5\r"
CMD_INPUT_VGA = "~0012 1\r"
CMD_INPUT_HDMI2 = "~0012 6\r"
CMD_FREEZE_ON = "~0080 1\r"
CMD_FREEZE_OFF = "~0080 0\r"
CMD_BLANK_ON = "~0011 1\r"
CMD_BLANK_OFF = "~0011 0\r"


# ---------------------------------------------------------------------------
# Main system model
# ---------------------------------------------------------------------------
class MasterCodeModel:
    """
    Models the MasterCode.axs logic including state machine, serial parsing,
    button guards, input selection, and UI feedback.
    """

    def __init__(self):
        # Core state variables (mirror DEFINE_VARIABLE)
        self.system_power = 0       # nSystemPower
        self.projector_power = 0    # nProjectorPower

        # Serial RX buffer (mirror sProjRxBuffer)
        self.rx_buffer = ""

        # Button feedback states: button_id -> on/off (bool)
        self.button_feedback = {}

        # Button ANI states: button_id -> state_number
        self.button_ani_state = {}

        # Button enable states: button_id -> enabled (bool)
        self.button_enabled = {}

        # Status bar
        self.status_text = ""
        self.status_color = ""

        # Current page
        self.current_page = "Home"

        # Sent serial commands log
        self.serial_commands_sent = []

        # TP commands log (for verification)
        self.tp_commands_sent = []

        # Input selection state
        self.active_input = None

        # Run startup
        self._startup()

    def _startup(self):
        """Mirror DEFINE_START block."""
        # ON button -> GRAY (State 1)
        self._set_button(BTN_PROJ_PWR_ON, feedback=False, ani_state=ButtonState.GRAY, enabled=True)
        # OFF button -> RED (State 1)
        self._set_button(BTN_PROJ_PWR_OFF, feedback=False, ani_state=ButtonState.RED, enabled=True)
        # HOME button -> GRAY (State 1)
        self._set_button(BTN_SYS_POWER_ON, feedback=False, ani_state=ButtonState.GRAY, enabled=True)

        # Disable input/control buttons
        for btn in [BTN_INP_HDMI, BTN_INP_VGA, BTN_INP_HDMI2, BTN_PROJ_FREEZE, BTN_PROJ_BLANK]:
            self.button_enabled[btn] = False

        # Status bar
        self.status_text = "System OFF"
        self.status_color = "#E74C3C"

    # -------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------
    def _set_button(self, btn_id, feedback=None, ani_state=None, enabled=None):
        if feedback is not None:
            self.button_feedback[btn_id] = feedback
        if ani_state is not None:
            self.button_ani_state[btn_id] = ani_state
        if enabled is not None:
            self.button_enabled[btn_id] = enabled

    def _send_serial(self, cmd):
        self.serial_commands_sent.append(cmd)

    def _enable_input_buttons(self, enable):
        for btn in [BTN_INP_HDMI, BTN_INP_VGA, BTN_INP_HDMI2, BTN_PROJ_FREEZE, BTN_PROJ_BLANK]:
            self.button_enabled[btn] = enable

    def _set_warming_ui(self):
        """Set UI to warming/starting state."""
        self._set_button(BTN_PROJ_PWR_ON, feedback=True, ani_state=ButtonState.AMBER, enabled=True)
        self._set_button(BTN_PROJ_PWR_OFF, feedback=False, ani_state=3, enabled=True)
        self._set_button(BTN_SYS_POWER_ON, feedback=True, ani_state=ButtonState.AMBER, enabled=True)
        self._enable_input_buttons(False)

    def _set_cooling_ui(self):
        """Set UI to cooling/shutting-down state."""
        self._set_button(BTN_PROJ_PWR_ON, feedback=False, ani_state=ButtonState.GRAY, enabled=True)
        self._set_button(BTN_PROJ_PWR_OFF, feedback=True, ani_state=ButtonState.DIMMED_GREEN, enabled=True)
        self._set_button(BTN_SYS_POWER_ON, feedback=True, ani_state=ButtonState.AMBER, enabled=True)
        self._enable_input_buttons(False)

    def _set_on_ui(self):
        """Set UI to projector ON state."""
        self._set_button(BTN_PROJ_PWR_ON, feedback=True, ani_state=ButtonState.GREEN, enabled=True)
        self._set_button(BTN_PROJ_PWR_OFF, feedback=False, ani_state=3, enabled=True)
        self._set_button(BTN_SYS_POWER_ON, feedback=True, ani_state=ButtonState.GREEN, enabled=True)
        self._enable_input_buttons(True)

    def _set_off_ui(self):
        """Set UI to projector OFF state."""
        self._set_button(BTN_PROJ_PWR_ON, feedback=False, ani_state=ButtonState.GRAY, enabled=True)
        self._set_button(BTN_PROJ_PWR_OFF, feedback=False, ani_state=ButtonState.RED, enabled=True)
        self._set_button(BTN_SYS_POWER_ON, feedback=False, ani_state=ButtonState.GRAY, enabled=True)
        self._enable_input_buttons(False)

    # -------------------------------------------------------------------
    # RS-232 response parsing (mirror data_event[dvProjector] string:)
    # -------------------------------------------------------------------
    def receive_serial_data(self, data):
        """
        Simulate receiving serial data from projector.
        Mirrors the data_event string handler with buffer parsing.
        """
        self.rx_buffer += data
        parsed_messages = []

        while "\r" in self.rx_buffer:
            idx = self.rx_buffer.index("\r")
            message = self.rx_buffer[:idx + 1]
            self.rx_buffer = self.rx_buffer[idx + 1:]

            parsed_messages.append(message)

            if "Ok1" in message:
                self._handle_projector_on()
            elif "Ok0" in message:
                self._handle_projector_off()
            elif "INFO1" in message:
                self._handle_warming()
            elif "INFO2" in message:
                self._handle_cooling()
            elif "P" in message:
                pass  # Command accepted acknowledgment

        return parsed_messages

    def _handle_projector_on(self):
        """Handle Ok1 response - projector confirmed ON."""
        self.projector_power = 1
        self.system_power = 1
        self._set_on_ui()
        self.status_text = "Projector ON"
        self.status_color = "#2ECC71"

    def _handle_projector_off(self):
        """Handle Ok0 response - projector confirmed OFF."""
        self.projector_power = 0
        self.system_power = 0
        self._set_off_ui()
        self.status_text = "System OFF"
        self.status_color = "#E74C3C"

    def _handle_warming(self):
        """Handle INFO1 response - projector warming up."""
        self._set_warming_ui()
        self.status_text = "Projector Warming Up"
        self.status_color = "#F39C12"

    def _handle_cooling(self):
        """Handle INFO2 response - projector cooling down."""
        self._set_cooling_ui()
        self.status_text = "Projector Cooling Down"
        self.status_color = "#F39C12"

    # -------------------------------------------------------------------
    # Button press handlers
    # -------------------------------------------------------------------
    def press_system_power(self):
        """
        Mirror button_event[dvTP, BTN_SYS_POWER_ON] push.
        Toggle system power on home page.
        """
        if self.system_power == 0:
            self._send_serial(CMD_POWER_ON)
            self._set_warming_ui()
            self.status_text = "Projector Starting..."
            self.status_color = "#F39C12"
            self.system_power = 1
            self.projector_power = 1
        else:
            self._send_serial(CMD_POWER_OFF)
            self._set_cooling_ui()
            self.status_text = "Projector Shutting Down..."
            self.status_color = "#F39C12"
            self.system_power = 0
            self.projector_power = 0

    def press_proj_power_on(self):
        """
        Mirror button_event[dvTP, BTN_PROJ_PWR_ON] push.
        Only fires when projector is off (guard).
        """
        if self.projector_power == 0:
            self._send_serial(CMD_POWER_ON)
            self._set_warming_ui()
            self.status_text = "Projector Starting..."
            self.status_color = "#F39C12"
            self.projector_power = 1
            self.system_power = 1

    def press_proj_power_off(self):
        """
        Mirror button_event[dvTP, BTN_PROJ_PWR_OFF] push.
        Only fires when projector is on (guard).
        """
        if self.projector_power == 1:
            self._send_serial(CMD_POWER_OFF)
            self._set_cooling_ui()
            self.status_text = "Projector Shutting Down..."
            self.status_color = "#F39C12"
            self.projector_power = 0
            self.system_power = 0

    def press_input_hdmi(self):
        """Mirror button_event[dvTP, BTN_INP_HDMI] push."""
        self._send_serial(CMD_INPUT_HDMI)
        self.button_feedback[BTN_INP_HDMI] = True
        self.button_feedback[BTN_INP_VGA] = False
        self.button_feedback[BTN_INP_HDMI2] = False
        self.active_input = "HDMI"

    def press_input_vga(self):
        """Mirror button_event[dvTP, BTN_INP_VGA] push."""
        self._send_serial(CMD_INPUT_VGA)
        self.button_feedback[BTN_INP_HDMI] = False
        self.button_feedback[BTN_INP_VGA] = True
        self.button_feedback[BTN_INP_HDMI2] = False
        self.active_input = "VGA"

    def press_input_hdmi2(self):
        """Mirror button_event[dvTP, BTN_INP_HDMI2] push."""
        self._send_serial(CMD_INPUT_HDMI2)
        self.button_feedback[BTN_INP_HDMI] = False
        self.button_feedback[BTN_INP_VGA] = False
        self.button_feedback[BTN_INP_HDMI2] = True
        self.active_input = "HDMI2"

    def press_freeze(self):
        """Mirror button_event[dvTP, BTN_PROJ_FREEZE] push (toggle)."""
        if self.button_feedback.get(BTN_PROJ_FREEZE, False):
            self._send_serial(CMD_FREEZE_OFF)
            self.button_feedback[BTN_PROJ_FREEZE] = False
        else:
            self._send_serial(CMD_FREEZE_ON)
            self.button_feedback[BTN_PROJ_FREEZE] = True

    def press_blank(self):
        """Mirror button_event[dvTP, BTN_PROJ_BLANK] push (toggle)."""
        if self.button_feedback.get(BTN_PROJ_BLANK, False):
            self._send_serial(CMD_BLANK_OFF)
            self.button_feedback[BTN_PROJ_BLANK] = False
        else:
            self._send_serial(CMD_BLANK_ON)
            self.button_feedback[BTN_PROJ_BLANK] = True

    def press_nav(self, button_id):
        """Mirror navigation button_events."""
        page_map = {
            BTN_NAV_HOME: "Home",
            BTN_NAV_DISPLAY: "Display",
            BTN_NAV_AUDIO: "Audio",
            BTN_NAV_PRESETS: "Presets",
        }
        if button_id in page_map:
            self.current_page = page_map[button_id]

    # -------------------------------------------------------------------
    # Heartbeat
    # -------------------------------------------------------------------
    def heartbeat_tick(self):
        """Mirror timeline_event[1] - polls projector status."""
        self._send_serial(CMD_STATUS_QUERY)

    # -------------------------------------------------------------------
    # Query helpers
    # -------------------------------------------------------------------
    def get_projector_state(self):
        """Derive high-level projector state from variables and UI."""
        # INFO1/INFO2 don't set power variables in the AMX code,
        # so we must also check status_text for transitional states.
        if self.status_text in ("Projector Warming Up", "Projector Starting..."):
            return ProjState.WARMING
        if self.status_text in ("Projector Cooling Down", "Projector Shutting Down..."):
            return ProjState.COOLING
        if self.projector_power == 1 and self.system_power == 1:
            return ProjState.ON
        return ProjState.OFF
