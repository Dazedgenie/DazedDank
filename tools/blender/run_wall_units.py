# Run inside Blender (Scripting tab > Open > Run Script): renders the wall-mounted climate units, then their icons.
import runpy
import sys

SCRIPT = r"C:\Users\Shado\Zomboid\dd_blender\room_art_v4.py"
for args in (["wall_heater", "wall_dehumidifier", "wall_humidifier"], ["icons", "WallHeater", "WallDehumidifier", "WallHumidifier"]):
    sys.argv = ["blender", "--"] + args
    runpy.run_path(SCRIPT, run_name="__main__")
open(r"C:\Users\Shado\Zomboid\dd_blender\renders\WALL_DONE.txt", "w").write("ok")
print("[DD] wall units finished")
