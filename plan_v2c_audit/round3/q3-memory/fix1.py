import re
p = 'm1_poly.py'
s = open(p).read()
s = s.replace("o['g_plain']['seen'] / o['g_bank']['seen']", "o['g_plain']['seen'] / max(1, o['g_bank']['seen'])")
s = s.replace("o['g_plain']['bytes'] / o['g_pre']['bytes']", "o['g_plain']['bytes'] / max(1, o['g_pre']['bytes'])")
s = s.replace("o['plain_below'] * B_FULL / o['r_bank']['model']", "o['plain_below'] * B_FULL / max(1, o['r_bank']['model'])")
s = s.replace("o['g_plain']['bytes'] / o['r_pre']['peak_bytes']", "o['g_plain']['bytes'] / max(1, o['r_pre']['peak_bytes'])")
open(p, 'w').write(s)
