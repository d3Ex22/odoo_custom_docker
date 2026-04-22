# Example: Convert simple attrs to direct expressions
# This script converts attrs="{'invisible': [('field', '=', value)]}" 
# to invisible="field == value"
#
# WARNING: This is a simplified example. Complex attrs with multiple
# conditions or 'and'/'or' logic require manual review.

from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


def convert_simple_domain(match):
    """Convert simple domain to Python expression."""
    attr_type = match.group(1)  # invisible, readonly, required
    field = match.group(2)
    operator = match.group(3)
    value = match.group(4)
    
    # Convert operator
    op_map = {
        '=': '==',
        '!=': '!=',
        '>': '>',
        '<': '<',
        '>=': '>=',
        '<=': '<=',
    }
    
    py_op = op_map.get(operator, operator)
    
    # Handle special values
    if value == 'True':
        if py_op == '==':
            return f'{attr_type}="{field}"'
        else:
            return f'{attr_type}="not {field}"'
    elif value == 'False':
        if py_op == '==':
            return f'{attr_type}="not {field}"'
        else:
            return f'{attr_type}="{field}"'
    else:
        return f'{attr_type}="{field} {py_op} {value}"'


def upgrade(file_manager: FileManager):
    """Convert simple attrs to direct Python expressions in XML views."""
    
    # Filter XML files in views folder
    files = [
        f for f in file_manager
        if f.path.suffix == '.xml'
        if 'views' in f.path.parts
    ]
    
    if not files:
        return
    
    # Pattern for simple single-condition attrs
    # Example: attrs="{'invisible': [('state', '=', 'draft')]}"
    simple_attrs = re.compile(
        r"attrs\s*=\s*[\"']\{\s*[\"']"
        r"(invisible|readonly|required)"
        r"[\"']\s*:\s*\[\s*\(\s*[\"']"
        r"(\w+)"  # field name
        r"[\"']\s*,\s*[\"']"
        r"([=!<>]+)"  # operator
        r"[\"']\s*,\s*"
        r"([^)]+)"  # value
        r"\s*\)\s*\]\s*\}[\"']"
    )
    
    for fileno, file in enumerate(files, start=1):
        content = file.content
        
        # Only process simple single-condition attrs
        content = simple_attrs.sub(convert_simple_domain, content)
        
        file.content = content
        file_manager.print_progress(fileno, len(files), file.path)

