"""Colours follow the DK design system tokens (DESIGN.md): one accent, soft surfaces, light and dark."""

LIGHT = dict(bg="#F5F6F8", surface="#FFFFFF", border="#E2E5EA", text="#14181F", text2="#5B6472",
             accent="#2F6BFF", danger="#D92D20", warn="#B54708", ok="#12873D", hover="#EEF1F6")
DARK = dict(bg="#101318", surface="#181C23", border="#2A303A", text="#ECEFF4", text2="#9AA4B2",
            accent="#5B8CFF", danger="#F97066", warn="#FDB022", ok="#47CD89", hover="#202632")


def stylesheet(dark: bool) -> str:
    c = DARK if dark else LIGHT
    return f"""
    QWidget {{ background: {c['bg']}; color: {c['text']}; font-size: 13px; }}
    #sidebar {{ background: {c['surface']}; border-right: 1px solid {c['border']}; }}
    #sidebar QListWidget {{ background: transparent; border: none; outline: none; }}
    #sidebar QListWidget::item {{ padding: 9px 12px; border-radius: 8px; margin: 2px 8px; }}
    #sidebar QListWidget::item:hover {{ background: {c['hover']}; }}
    #sidebar QListWidget::item:selected {{ background: {c['accent']}; color: #FFFFFF; }}
    #brand {{ background: transparent; font-size: 15px; font-weight: 600; padding: 14px 16px 6px 16px; }}
    #title {{ font-size: 20px; font-weight: 600; }}
    #subtitle, #muted {{ color: {c['text2']}; }}
    #card {{ background: {c['surface']}; border: 1px solid {c['border']}; border-radius: 12px; }}
    #card QLabel {{ background: transparent; }}
    #cardValue {{ font-size: 24px; font-weight: 600; }}
    #banner {{ background: {c['surface']}; border: 1px solid {c['warn']}; border-radius: 10px;
               color: {c['warn']}; padding: 8px 12px; }}
    QTableWidget {{ background: {c['surface']}; border: 1px solid {c['border']}; border-radius: 10px;
                    gridline-color: transparent; alternate-background-color: {c['bg']}; }}
    QHeaderView::section {{ background: {c['surface']}; color: {c['text2']}; border: none;
                            border-bottom: 1px solid {c['border']}; padding: 6px 8px; }}
    QLineEdit {{ background: {c['surface']}; border: 1px solid {c['border']}; border-radius: 8px; padding: 6px 10px; }}
    QPushButton {{ background: {c['accent']}; color: #FFFFFF; border: none; border-radius: 8px; padding: 7px 14px; }}
    QPushButton:disabled {{ background: {c['border']}; color: {c['text2']}; }}
    """


def severity_color(severity: str, dark: bool) -> str:
    c = DARK if dark else LIGHT
    s = severity.lower()
    if s in ("critical", "high"):
        return c["danger"]
    if s in ("moderate", "medium"):
        return c["warn"]
    return c["text2"]
