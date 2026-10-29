"""Draws the app icon (accent-blue tile with a white box) so no binary asset is checked in."""
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QColor, QGuiApplication, QImage, QPainter, QPen, QPolygonF

app = QGuiApplication([])
size = 256
img = QImage(size, size, QImage.Format_ARGB32)
img.fill(Qt.transparent)
p = QPainter(img)
p.setRenderHint(QPainter.Antialiasing)
p.setBrush(QColor("#2F6BFF"))
p.setPen(Qt.NoPen)
p.drawRoundedRect(0, 0, size, size, 56, 56)
p.setPen(QPen(QColor("white"), 12, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
p.setBrush(Qt.NoBrush)
c = size / 2
top = QPolygonF([QPointF(c, 62), QPointF(c + 70, 100), QPointF(c, 138), QPointF(c - 70, 100)])
p.drawPolygon(top)
p.drawLine(QPointF(c - 70, 100), QPointF(c - 70, 168))
p.drawLine(QPointF(c + 70, 100), QPointF(c + 70, 168))
p.drawLine(QPointF(c, 138), QPointF(c, 206))
p.drawLine(QPointF(c - 70, 168), QPointF(c, 206))
p.drawLine(QPointF(c + 70, 168), QPointF(c, 206))
p.end()
img.save(sys.argv[1])
