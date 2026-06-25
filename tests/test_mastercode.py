"""
Unit tests for MasterCode.axs logic via the Python model.

Covers:
  1. Startup / initialization defaults
  2. RS-232 serial response parsing (buffer, Ok1, Ok0, INFO1, INFO2, P)
  3. Power state machine transitions
  4. Button guard conditions (power on only when off, power off only when on)
  5. Input selection mutual exclusion (HDMI / VGA / HDMI2)
  6. Freeze and Blank toggle logic
  7. Navigation page routing
  8. Heartbeat status query
  9. UI feedback consistency (button ANI states, status bar text/color)
 10. Edge cases (partial serial data, multiple messages in one chunk)
"""

import pytest

from amx_model import (
    BTN_INP_HDMI,
    BTN_INP_HDMI2,
    BTN_INP_VGA,
    BTN_NAV_AUDIO,
    BTN_NAV_DISPLAY,
    BTN_NAV_HOME,
    BTN_NAV_PRESETS,
    BTN_PROJ_BLANK,
    BTN_PROJ_FREEZE,
    BTN_PROJ_PWR_OFF,
    BTN_PROJ_PWR_ON,
    BTN_SYS_POWER_ON,
    CMD_BLANK_OFF,
    CMD_BLANK_ON,
    CMD_FREEZE_OFF,
    CMD_FREEZE_ON,
    CMD_INPUT_HDMI,
    CMD_INPUT_HDMI2,
    CMD_INPUT_VGA,
    CMD_POWER_OFF,
    CMD_POWER_ON,
    CMD_STATUS_QUERY,
    ButtonState,
    MasterCodeModel,
    ProjState,
)


# ===================================================================
# Fixtures
# ===================================================================

@pytest.fixture
def model():
    """Fresh MasterCodeModel (system just booted)."""
    return MasterCodeModel()


@pytest.fixture
def model_on(model):
    """Model with projector confirmed ON (Ok1 received)."""
    model.receive_serial_data("Ok1\r")
    model.serial_commands_sent.clear()
    return model


# ===================================================================
# 1. Startup / Initialization
# ===================================================================

class TestStartup:

    def test_system_power_starts_off(self, model):
        assert model.system_power == 0

    def test_projector_power_starts_off(self, model):
        assert model.projector_power == 0

    def test_on_button_gray_at_boot(self, model):
        assert model.button_ani_state[BTN_PROJ_PWR_ON] == ButtonState.GRAY
        assert model.button_feedback[BTN_PROJ_PWR_ON] is False

    def test_off_button_red_at_boot(self, model):
        assert model.button_ani_state[BTN_PROJ_PWR_OFF] == ButtonState.RED
        assert model.button_feedback[BTN_PROJ_PWR_OFF] is False

    def test_home_button_gray_at_boot(self, model):
        assert model.button_ani_state[BTN_SYS_POWER_ON] == ButtonState.GRAY
        assert model.button_feedback[BTN_SYS_POWER_ON] is False

    def test_input_buttons_disabled_at_boot(self, model):
        for btn in [BTN_INP_HDMI, BTN_INP_VGA, BTN_INP_HDMI2,
                     BTN_PROJ_FREEZE, BTN_PROJ_BLANK]:
            assert model.button_enabled[btn] is False

    def test_status_bar_off_at_boot(self, model):
        assert model.status_text == "System OFF"
        assert model.status_color == "#E74C3C"

    def test_rx_buffer_empty_at_boot(self, model):
        assert model.rx_buffer == ""

    def test_no_serial_commands_at_boot(self, model):
        assert model.serial_commands_sent == []

    def test_on_off_buttons_enabled_at_boot(self, model):
        assert model.button_enabled[BTN_PROJ_PWR_ON] is True
        assert model.button_enabled[BTN_PROJ_PWR_OFF] is True


# ===================================================================
# 2. RS-232 Serial Response Parsing
# ===================================================================

class TestSerialParsing:

    def test_ok1_sets_projector_on(self, model):
        model.receive_serial_data("Ok1\r")
        assert model.projector_power == 1
        assert model.system_power == 1

    def test_ok0_sets_projector_off(self, model):
        model.receive_serial_data("Ok1\r")
        model.receive_serial_data("Ok0\r")
        assert model.projector_power == 0
        assert model.system_power == 0

    def test_info1_warming_status(self, model):
        model.receive_serial_data("INFO1\r")
        assert model.status_text == "Projector Warming Up"
        assert model.status_color == "#F39C12"

    def test_info2_cooling_status(self, model):
        model.receive_serial_data("INFO2\r")
        assert model.status_text == "Projector Cooling Down"
        assert model.status_color == "#F39C12"

    def test_p_ack_no_state_change(self, model):
        model.receive_serial_data("P\r")
        assert model.system_power == 0
        assert model.projector_power == 0
        assert model.status_text == "System OFF"

    def test_partial_data_buffered(self, model):
        """Data that arrives without CR stays in the buffer."""
        model.receive_serial_data("Ok")
        assert model.rx_buffer == "Ok"
        assert model.projector_power == 0

    def test_partial_then_complete(self, model):
        """Buffer accumulates until CR is received."""
        model.receive_serial_data("Ok")
        model.receive_serial_data("1\r")
        assert model.rx_buffer == ""
        assert model.projector_power == 1

    def test_multiple_messages_in_one_chunk(self, model):
        """Two messages arrive in a single data chunk."""
        msgs = model.receive_serial_data("Ok1\rOk0\r")
        assert len(msgs) == 2
        assert model.projector_power == 0

    def test_buffer_cleared_after_parsing(self, model):
        model.receive_serial_data("Ok1\r")
        assert model.rx_buffer == ""

    def test_trailing_partial_preserved(self, model):
        """After parsing complete messages, leftover stays in buffer."""
        model.receive_serial_data("Ok1\rINF")
        assert model.projector_power == 1
        assert model.rx_buffer == "INF"

    def test_ok1_returns_parsed_message(self, model):
        msgs = model.receive_serial_data("Ok1\r")
        assert len(msgs) == 1
        assert "Ok1" in msgs[0]


# ===================================================================
# 3. Power State Machine
# ===================================================================

class TestPowerStateMachine:

    def test_off_to_warming_via_ok1_response(self, model):
        """Boot -> receive Ok1 -> ON."""
        model.receive_serial_data("Ok1\r")
        assert model.get_projector_state() == ProjState.ON

    def test_on_to_off_via_ok0_response(self, model_on):
        model_on.receive_serial_data("Ok0\r")
        assert model_on.get_projector_state() == ProjState.OFF

    def test_warming_state_via_info1(self, model):
        model.receive_serial_data("INFO1\r")
        assert model.get_projector_state() == ProjState.WARMING

    def test_cooling_state_via_info2(self, model):
        model.receive_serial_data("INFO2\r")
        assert model.get_projector_state() == ProjState.COOLING

    def test_full_cycle_off_warming_on_cooling_off(self, model):
        assert model.get_projector_state() == ProjState.OFF

        model.press_system_power()
        assert model.get_projector_state() == ProjState.WARMING

        model.receive_serial_data("Ok1\r")
        assert model.get_projector_state() == ProjState.ON

        model.press_system_power()
        assert model.get_projector_state() == ProjState.COOLING

        model.receive_serial_data("Ok0\r")
        assert model.get_projector_state() == ProjState.OFF


# ===================================================================
# 4. Button Guard Logic
# ===================================================================

class TestButtonGuards:

    def test_proj_on_ignored_when_already_on(self, model_on):
        """Pressing power ON when already on should not send a command."""
        model_on.press_proj_power_on()
        assert model_on.serial_commands_sent == []

    def test_proj_off_ignored_when_already_off(self, model):
        """Pressing power OFF when already off should not send a command."""
        model.press_proj_power_off()
        assert model.serial_commands_sent == []

    def test_proj_on_fires_when_off(self, model):
        model.press_proj_power_on()
        assert CMD_POWER_ON in model.serial_commands_sent

    def test_proj_off_fires_when_on(self, model_on):
        model_on.press_proj_power_off()
        assert CMD_POWER_OFF in model_on.serial_commands_sent

    def test_system_toggle_on_then_off(self, model):
        model.press_system_power()
        assert CMD_POWER_ON in model.serial_commands_sent

        model.serial_commands_sent.clear()
        model.press_system_power()
        assert CMD_POWER_OFF in model.serial_commands_sent

    def test_double_on_press_no_duplicate_command(self, model):
        """First press sends command; second is guarded."""
        model.press_proj_power_on()
        assert len(model.serial_commands_sent) == 1
        model.press_proj_power_on()
        assert len(model.serial_commands_sent) == 1

    def test_double_off_press_no_duplicate_command(self, model_on):
        model_on.press_proj_power_off()
        assert len(model_on.serial_commands_sent) == 1
        model_on.press_proj_power_off()
        assert len(model_on.serial_commands_sent) == 1


# ===================================================================
# 5. Input Selection (Mutual Exclusion)
# ===================================================================

class TestInputSelection:

    def test_hdmi_selected(self, model_on):
        model_on.press_input_hdmi()
        assert model_on.button_feedback[BTN_INP_HDMI] is True
        assert model_on.button_feedback[BTN_INP_VGA] is False
        assert model_on.button_feedback[BTN_INP_HDMI2] is False

    def test_vga_selected(self, model_on):
        model_on.press_input_vga()
        assert model_on.button_feedback[BTN_INP_VGA] is True
        assert model_on.button_feedback[BTN_INP_HDMI] is False
        assert model_on.button_feedback[BTN_INP_HDMI2] is False

    def test_hdmi2_selected(self, model_on):
        model_on.press_input_hdmi2()
        assert model_on.button_feedback[BTN_INP_HDMI2] is True
        assert model_on.button_feedback[BTN_INP_HDMI] is False
        assert model_on.button_feedback[BTN_INP_VGA] is False

    def test_switching_deselects_previous(self, model_on):
        model_on.press_input_hdmi()
        assert model_on.active_input == "HDMI"

        model_on.press_input_vga()
        assert model_on.active_input == "VGA"
        assert model_on.button_feedback[BTN_INP_HDMI] is False

    def test_hdmi_sends_correct_command(self, model_on):
        model_on.press_input_hdmi()
        assert CMD_INPUT_HDMI in model_on.serial_commands_sent

    def test_vga_sends_correct_command(self, model_on):
        model_on.press_input_vga()
        assert CMD_INPUT_VGA in model_on.serial_commands_sent

    def test_hdmi2_sends_correct_command(self, model_on):
        model_on.press_input_hdmi2()
        assert CMD_INPUT_HDMI2 in model_on.serial_commands_sent

    def test_rapid_switching(self, model_on):
        model_on.press_input_hdmi()
        model_on.press_input_vga()
        model_on.press_input_hdmi2()
        assert model_on.active_input == "HDMI2"
        assert model_on.button_feedback[BTN_INP_HDMI] is False
        assert model_on.button_feedback[BTN_INP_VGA] is False
        assert model_on.button_feedback[BTN_INP_HDMI2] is True


# ===================================================================
# 6. Freeze / Blank Toggle
# ===================================================================

class TestFreezeToggle:

    def test_freeze_on(self, model_on):
        model_on.press_freeze()
        assert model_on.button_feedback[BTN_PROJ_FREEZE] is True
        assert CMD_FREEZE_ON in model_on.serial_commands_sent

    def test_freeze_off(self, model_on):
        model_on.press_freeze()
        model_on.serial_commands_sent.clear()
        model_on.press_freeze()
        assert model_on.button_feedback[BTN_PROJ_FREEZE] is False
        assert CMD_FREEZE_OFF in model_on.serial_commands_sent

    def test_freeze_toggle_cycle(self, model_on):
        model_on.press_freeze()
        assert model_on.button_feedback[BTN_PROJ_FREEZE] is True
        model_on.press_freeze()
        assert model_on.button_feedback[BTN_PROJ_FREEZE] is False
        model_on.press_freeze()
        assert model_on.button_feedback[BTN_PROJ_FREEZE] is True


class TestBlankToggle:

    def test_blank_on(self, model_on):
        model_on.press_blank()
        assert model_on.button_feedback[BTN_PROJ_BLANK] is True
        assert CMD_BLANK_ON in model_on.serial_commands_sent

    def test_blank_off(self, model_on):
        model_on.press_blank()
        model_on.serial_commands_sent.clear()
        model_on.press_blank()
        assert model_on.button_feedback[BTN_PROJ_BLANK] is False
        assert CMD_BLANK_OFF in model_on.serial_commands_sent

    def test_blank_toggle_cycle(self, model_on):
        model_on.press_blank()
        assert model_on.button_feedback[BTN_PROJ_BLANK] is True
        model_on.press_blank()
        assert model_on.button_feedback[BTN_PROJ_BLANK] is False
        model_on.press_blank()
        assert model_on.button_feedback[BTN_PROJ_BLANK] is True


# ===================================================================
# 7. Navigation
# ===================================================================

class TestNavigation:

    def test_nav_home(self, model):
        model.press_nav(BTN_NAV_HOME)
        assert model.current_page == "Home"

    def test_nav_display(self, model):
        model.press_nav(BTN_NAV_DISPLAY)
        assert model.current_page == "Display"

    def test_nav_audio(self, model):
        model.press_nav(BTN_NAV_AUDIO)
        assert model.current_page == "Audio"

    def test_nav_presets(self, model):
        model.press_nav(BTN_NAV_PRESETS)
        assert model.current_page == "Presets"

    def test_nav_invalid_button_no_change(self, model):
        model.press_nav(999)
        assert model.current_page == "Home"

    def test_nav_sequence(self, model):
        model.press_nav(BTN_NAV_DISPLAY)
        assert model.current_page == "Display"
        model.press_nav(BTN_NAV_AUDIO)
        assert model.current_page == "Audio"
        model.press_nav(BTN_NAV_HOME)
        assert model.current_page == "Home"


# ===================================================================
# 8. Heartbeat
# ===================================================================

class TestHeartbeat:

    def test_heartbeat_sends_status_query(self, model):
        model.heartbeat_tick()
        assert CMD_STATUS_QUERY in model.serial_commands_sent

    def test_multiple_heartbeats(self, model):
        model.heartbeat_tick()
        model.heartbeat_tick()
        model.heartbeat_tick()
        assert model.serial_commands_sent.count(CMD_STATUS_QUERY) == 3


# ===================================================================
# 9. UI Feedback Consistency
# ===================================================================

class TestUIFeedback:

    def test_on_state_button_colors(self, model):
        model.receive_serial_data("Ok1\r")
        assert model.button_ani_state[BTN_PROJ_PWR_ON] == ButtonState.GREEN
        assert model.button_ani_state[BTN_SYS_POWER_ON] == ButtonState.GREEN

    def test_off_state_button_colors(self, model):
        model.receive_serial_data("Ok1\r")
        model.receive_serial_data("Ok0\r")
        assert model.button_ani_state[BTN_PROJ_PWR_ON] == ButtonState.GRAY
        assert model.button_ani_state[BTN_PROJ_PWR_OFF] == ButtonState.RED

    def test_warming_state_button_colors(self, model):
        model.receive_serial_data("INFO1\r")
        assert model.button_ani_state[BTN_PROJ_PWR_ON] == ButtonState.AMBER
        assert model.button_ani_state[BTN_SYS_POWER_ON] == ButtonState.AMBER

    def test_cooling_state_button_colors(self, model):
        model.receive_serial_data("INFO2\r")
        assert model.button_ani_state[BTN_PROJ_PWR_ON] == ButtonState.GRAY
        assert model.button_ani_state[BTN_PROJ_PWR_OFF] == ButtonState.DIMMED_GREEN

    def test_on_state_status_bar(self, model):
        model.receive_serial_data("Ok1\r")
        assert model.status_text == "Projector ON"
        assert model.status_color == "#2ECC71"

    def test_off_state_status_bar(self, model):
        assert model.status_text == "System OFF"
        assert model.status_color == "#E74C3C"

    def test_warming_status_bar(self, model):
        model.receive_serial_data("INFO1\r")
        assert model.status_text == "Projector Warming Up"
        assert model.status_color == "#F39C12"

    def test_cooling_status_bar(self, model):
        model.receive_serial_data("INFO2\r")
        assert model.status_text == "Projector Cooling Down"
        assert model.status_color == "#F39C12"

    def test_input_buttons_enabled_when_on(self, model):
        model.receive_serial_data("Ok1\r")
        for btn in [BTN_INP_HDMI, BTN_INP_VGA, BTN_INP_HDMI2,
                     BTN_PROJ_FREEZE, BTN_PROJ_BLANK]:
            assert model.button_enabled[btn] is True

    def test_input_buttons_disabled_when_off(self, model):
        model.receive_serial_data("Ok1\r")
        model.receive_serial_data("Ok0\r")
        for btn in [BTN_INP_HDMI, BTN_INP_VGA, BTN_INP_HDMI2,
                     BTN_PROJ_FREEZE, BTN_PROJ_BLANK]:
            assert model.button_enabled[btn] is False

    def test_input_buttons_disabled_during_warming(self, model):
        model.receive_serial_data("INFO1\r")
        for btn in [BTN_INP_HDMI, BTN_INP_VGA, BTN_INP_HDMI2,
                     BTN_PROJ_FREEZE, BTN_PROJ_BLANK]:
            assert model.button_enabled[btn] is False

    def test_input_buttons_disabled_during_cooling(self, model):
        model.receive_serial_data("INFO2\r")
        for btn in [BTN_INP_HDMI, BTN_INP_VGA, BTN_INP_HDMI2,
                     BTN_PROJ_FREEZE, BTN_PROJ_BLANK]:
            assert model.button_enabled[btn] is False

    def test_power_buttons_always_enabled(self, model):
        for response in ["Ok1\r", "Ok0\r", "INFO1\r", "INFO2\r"]:
            model.receive_serial_data(response)
            assert model.button_enabled[BTN_PROJ_PWR_ON] is True
            assert model.button_enabled[BTN_PROJ_PWR_OFF] is True

    def test_system_power_on_sets_warming_ui(self, model):
        model.press_system_power()
        assert model.button_ani_state[BTN_PROJ_PWR_ON] == ButtonState.AMBER
        assert model.status_text == "Projector Starting..."

    def test_system_power_off_sets_cooling_ui(self, model):
        model.press_system_power()
        model.press_system_power()
        assert model.button_ani_state[BTN_PROJ_PWR_ON] == ButtonState.GRAY
        assert model.status_text == "Projector Shutting Down..."


# ===================================================================
# 10. Edge Cases
# ===================================================================

class TestEdgeCases:

    def test_empty_serial_data(self, model):
        msgs = model.receive_serial_data("")
        assert msgs == []
        assert model.rx_buffer == ""

    def test_cr_only(self, model):
        msgs = model.receive_serial_data("\r")
        assert len(msgs) == 1
        assert model.projector_power == 0

    def test_unknown_response_no_crash(self, model):
        msgs = model.receive_serial_data("UNKNOWN_RESPONSE\r")
        assert len(msgs) == 1
        assert model.projector_power == 0

    def test_multiple_ok1_idempotent(self, model):
        model.receive_serial_data("Ok1\r")
        model.receive_serial_data("Ok1\r")
        assert model.projector_power == 1
        assert model.system_power == 1

    def test_multiple_ok0_idempotent(self, model):
        model.receive_serial_data("Ok0\r")
        model.receive_serial_data("Ok0\r")
        assert model.projector_power == 0
        assert model.system_power == 0

    def test_interleaved_partial_data(self, model):
        """Simulate fragmented serial data arriving in small chunks."""
        model.receive_serial_data("O")
        model.receive_serial_data("k")
        model.receive_serial_data("1")
        model.receive_serial_data("\r")
        assert model.projector_power == 1

    def test_large_buffer_accumulation(self, model):
        """Many small fragments before a CR."""
        for ch in "INFO1":
            model.receive_serial_data(ch)
        assert model.rx_buffer == "INFO1"
        model.receive_serial_data("\r")
        assert model.status_text == "Projector Warming Up"

    def test_rapid_state_changes(self, model):
        """Quick succession of conflicting responses."""
        model.receive_serial_data("Ok1\rOk0\rOk1\r")
        assert model.projector_power == 1

    def test_system_power_toggle_from_on_state(self, model_on):
        """Toggle system power when starting from confirmed-ON state."""
        model_on.press_system_power()
        assert model_on.system_power == 0
        assert CMD_POWER_OFF in model_on.serial_commands_sent

    def test_proj_power_on_then_system_toggle_off(self, model):
        """Use display-page ON, then home-page toggle OFF."""
        model.press_proj_power_on()
        assert model.projector_power == 1
        model.press_system_power()
        assert model.system_power == 0
        assert model.projector_power == 0


# ===================================================================
# 11. Command Format Verification
# ===================================================================

class TestCommandFormats:

    def test_power_on_command_format(self, model):
        model.press_proj_power_on()
        assert model.serial_commands_sent[-1] == "~0000 1\r"

    def test_power_off_command_format(self, model_on):
        model_on.press_proj_power_off()
        assert model_on.serial_commands_sent[-1] == "~0000 0\r"

    def test_status_query_command_format(self, model):
        model.heartbeat_tick()
        assert model.serial_commands_sent[-1] == "~00124 1\r"

    def test_hdmi_input_command_format(self, model_on):
        model_on.press_input_hdmi()
        assert model_on.serial_commands_sent[-1] == "~0012 5\r"

    def test_vga_input_command_format(self, model_on):
        model_on.press_input_vga()
        assert model_on.serial_commands_sent[-1] == "~0012 1\r"

    def test_hdmi2_input_command_format(self, model_on):
        model_on.press_input_hdmi2()
        assert model_on.serial_commands_sent[-1] == "~0012 6\r"

    def test_freeze_on_command_format(self, model_on):
        model_on.press_freeze()
        assert model_on.serial_commands_sent[-1] == "~0080 1\r"

    def test_freeze_off_command_format(self, model_on):
        model_on.press_freeze()
        model_on.press_freeze()
        assert model_on.serial_commands_sent[-1] == "~0080 0\r"

    def test_blank_on_command_format(self, model_on):
        model_on.press_blank()
        assert model_on.serial_commands_sent[-1] == "~0011 1\r"

    def test_blank_off_command_format(self, model_on):
        model_on.press_blank()
        model_on.press_blank()
        assert model_on.serial_commands_sent[-1] == "~0011 0\r"
