#!/usr/bin/env python3
import sys
import time
import threading
from enum import Enum
from PyQt6 import QtWidgets, QtCore, QtGui
from pynput import keyboard, mouse
from pynput.keyboard import Key, KeyCode

# --- Configuration ---
GRID_ROWS = 26
GRID_COLS = 26
LINE_COLOR = QtGui.QColor(0, 255, 255, 76)
TEXT_COLOR = QtGui.QColor(255, 255, 0)
BG_COLOR = QtGui.QColor(0, 0, 0, 25)
LABEL_BG_COLOR = QtGui.QColor(0, 0, 0, 180)
FOCUS_COLOR = QtGui.QColor(0, 255, 0, 76)
CURSOR_STEP = 15
TAP_THRESHOLD = 0.4
VERSION = "1.5.0-STABLE-FINAL"

class AppState(Enum):
    HIDDEN = 0
    GRID_SELECTION = 1
    FINE_TUNING = 2
    SCROLLING = 3

class GridOverlay(QtWidgets.QWidget):
    def __init__(self):
        super().__init__()
        self.state = AppState.HIDDEN
        self.first_char = None
        self.screen_geo = None
        
        self.setWindowFlags(
            QtCore.Qt.WindowType.FramelessWindowHint |
            QtCore.Qt.WindowType.WindowStaysOnTopHint |
            QtCore.Qt.WindowType.Tool |
            QtCore.Qt.WindowType.WindowTransparentForInput
        )
        self.setAttribute(QtCore.Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(QtCore.Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setAttribute(QtCore.Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        
        screen = QtWidgets.QApplication.primaryScreen()
        self.screen_geo = screen.geometry()
        self.setGeometry(self.screen_geo)

    def update_state(self, new_state):
        self.state = new_state
        if new_state == AppState.HIDDEN:
            self.first_char = None
            self.hide()
        else:
            self.show()
            self.raise_()
            self.update()

    def paintEvent(self, event):
        if self.state == AppState.HIDDEN: return
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)
        self.draw_status_hint(painter)
        if self.state == AppState.GRID_SELECTION:
            self.draw_grid(painter)

    def draw_status_hint(self, painter):
        text = ""
        if self.state == AppState.GRID_SELECTION: text = "Grid Mode | A-Z: Select | ESC: Exit"
        elif self.state == AppState.FINE_TUNING: text = "Fine Tune | HJKL: Move | Space: Click | M: Right Click | T: Drag | ESC: Exit"
        elif self.state == AppState.SCROLLING: text = "Scroll Mode | J/K: Scroll | ESC: Exit"

        font = QtGui.QFont("Arial", 12)
        painter.setFont(font)
        metrics = QtGui.QFontMetrics(font)
        rect = metrics.boundingRect(text)
        w, h = rect.width() + 20, rect.height() + 20
        x, y = self.width() - w - 20, 20
        painter.setBrush(QtGui.QColor(0, 0, 0, 150))
        painter.setPen(QtCore.Qt.PenStyle.NoPen)
        painter.drawRoundedRect(x, y, w, h, 5, 5)
        painter.setPen(QtGui.QColor(255, 255, 255))
        painter.drawText(x + 10, y + 10 + metrics.ascent(), text)

    def draw_grid(self, painter):
        w, h = self.width(), self.height()
        cell_w, cell_h = w / GRID_COLS, h / GRID_ROWS
        painter.setPen(QtGui.QPen(LINE_COLOR, 1))
        for i in range(1, GRID_COLS):
            x = i * cell_w
            painter.drawLine(int(x), 0, int(x), h)
        for i in range(1, GRID_ROWS):
            y = i * cell_h
            painter.drawLine(0, int(y), w, int(y))
        letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        painter.setFont(QtGui.QFont("Monospace", 14, QtGui.QFont.Weight.Bold))
        for r in range(GRID_ROWS):
            if self.first_char and letters[r] != self.first_char: continue
            for c in range(GRID_COLS):
                label = letters[r] + letters[c]
                x, y = c * cell_w, r * cell_h
                if self.first_char: painter.fillRect(QtCore.QRectF(x, y, cell_w, cell_h), FOCUS_COLOR)
                painter.setBrush(LABEL_BG_COLOR)
                painter.setPen(QtCore.Qt.PenStyle.NoPen)
                lx, ly = int(x + (cell_w - 30) / 2), int(y + (cell_h - 25) / 2)
                painter.drawRoundedRect(lx, ly, 30, 25, 4, 4)
                painter.setPen(TEXT_COLOR)
                painter.drawText(QtCore.QRectF(x, y, cell_w, cell_h), QtCore.Qt.AlignmentFlag.AlignCenter, label)

class Controller(QtCore.QObject):
    state_changed = QtCore.pyqtSignal(object)
    request_paint = QtCore.pyqtSignal()
    request_reset = QtCore.pyqtSignal()

    def __init__(self):
        super().__init__()
        self.app_state = AppState.HIDDEN
        self.mouse_ctl = mouse.Controller()
        self.keyboard_ctl = keyboard.Controller()
        self.last_alt_time = 0
        self.potential_toggle = False
        self.first_char = None
        self.is_dragging = False

        self.listener = keyboard.Listener(on_press=self.on_press, on_release=self.on_release)
        self.listener.start()
        self.request_reset.connect(self.perform_reset)

    def set_overlay(self, overlay):
        self.overlay = overlay
        self.state_changed.connect(overlay.update_state)
        self.request_paint.connect(overlay.update)

    def change_state(self, new_state):
        self.app_state = new_state
        if new_state == AppState.HIDDEN or new_state == AppState.GRID_SELECTION:
            self.first_char = None
            self.overlay.first_char = None
        if new_state == AppState.HIDDEN:
            if self.is_dragging: self.toggle_drag(False)
        self.state_changed.emit(new_state)

    def perform_reset(self):
        # 强制回到网格选择状态，不消失窗口
        print("DEBUG: Executing Reset")
        self.change_state(AppState.GRID_SELECTION)

    def toggle_drag(self, enable):
        if enable:
            # 拖拽也需要瞬间隐藏来穿透初始点击
            self.state_changed.emit(AppState.HIDDEN)
            time.sleep(0.02)
            self.mouse_ctl.press(mouse.Button.left)
            time.sleep(0.02)
            self.state_changed.emit(AppState.FINE_TUNING)
        else:
            self.mouse_ctl.release(mouse.Button.left)
        self.is_dragging = enable

    def async_click(self, button):
        def _click():
            # 关键：点击时瞬间隐藏，穿透遮挡
            current_mode = self.app_state
            self.state_changed.emit(AppState.HIDDEN)
            time.sleep(0.03) 
            self.mouse_ctl.press(button)
            time.sleep(0.05)
            self.mouse_ctl.release(button)
            time.sleep(0.03)
            # 点击完立即恢复
            if current_mode != AppState.HIDDEN:
                self.state_changed.emit(current_mode)
        threading.Thread(target=_click, daemon=True).start()

    def on_press(self, key):
        if key == Key.alt_l:
            if not self.potential_toggle:
                self.potential_toggle = True
                self.last_alt_time = time.time()
            return
        if self.app_state == AppState.HIDDEN: return
        if key == Key.esc: self.change_state(AppState.HIDDEN); return
        if self.app_state == AppState.GRID_SELECTION:
            if key == Key.backspace:
                self.first_char = None; self.overlay.first_char = None
                self.request_paint.emit()
            else:
                char = self.get_char(key)
                if char and "A" <= char <= "Z":
                    if self.first_char is None:
                        self.first_char = char; self.overlay.first_char = char
                        self.request_paint.emit()
                    else:
                        self.select_grid(self.first_char + char)
            return
        elif self.app_state == AppState.FINE_TUNING:
            char = self.get_char(key)
            if char == 'H': self.mouse_ctl.move(-CURSOR_STEP, 0)
            elif char == 'L': self.mouse_ctl.move(CURSOR_STEP, 0)
            elif char == 'K': self.mouse_ctl.move(0, -CURSOR_STEP)
            elif char == 'J': self.mouse_ctl.move(0, CURSOR_STEP)
            elif key == Key.space: self.async_click(mouse.Button.left)
            elif char == 'M': self.async_click(mouse.Button.right)
            elif char == 'T' or char == 'V':
                if not self.is_dragging: self.toggle_drag(True)
            elif char == 'O': self.change_state(AppState.SCROLLING)
            elif key == Key.enter:
                self.keyboard_ctl.press(Key.ctrl); self.keyboard_ctl.press('c')
                self.keyboard_ctl.release('c'); self.keyboard_ctl.release(Key.ctrl)
                self.change_state(AppState.HIDDEN)
            elif key == Key.backspace:
                self.change_state(AppState.GRID_SELECTION)
            return
        elif self.app_state == AppState.SCROLLING:
            char = self.get_char(key)
            if char == 'J': self.mouse_ctl.scroll(0, -1)
            elif char == 'K': self.mouse_ctl.scroll(0, 1)
            return

    def on_release(self, key):
        if key == Key.alt_l:
            if self.potential_toggle:
                duration = time.time() - self.last_alt_time
                if duration < TAP_THRESHOLD:
                    self.request_reset.emit()
            self.potential_toggle = False
        if self.app_state == AppState.FINE_TUNING:
            char = self.get_char(key)
            if (char == 'T' or char == 'V') and self.is_dragging: self.toggle_drag(False)

    def get_char(self, key):
        if hasattr(key, 'char') and key.char: return key.char.upper()
        try: return chr(key.vk).upper()
        except: return None

    def select_grid(self, label):
        row, col = ord(label[0]) - 65, ord(label[1]) - 65
        if 0 <= row < GRID_ROWS and 0 <= col < GRID_COLS:
            geo = self.overlay.screen_geo
            cw, ch = geo.width() / GRID_COLS, geo.height() / GRID_ROWS
            self.mouse_ctl.position = (geo.x() + col * cw + cw / 2, geo.y() + row * ch + ch / 2)
            self.change_state(AppState.FINE_TUNING)

def main():
    app = QtWidgets.QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    controller = Controller()
    overlay = GridOverlay()
    controller.set_overlay(overlay)
    print(f"GridClicker Started ({VERSION}).")
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
