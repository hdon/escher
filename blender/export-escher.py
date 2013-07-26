# Escher map export script. Copyright 2013 Don Viszneki <don@codebad.com> all rights reserved

bl_info = {
    "name":         "Export Escher Map Format(.esc)",
    "author":       "Don Viszneki (don@codebad.com)",
    "version":      (1, 0),
    "blender":      (2, 68, 0),
    "location":     "File > Export > Escher (.esc)",
    "description":  "Export Escher map (.esc)",
    "warning":      "Still under development",
    "category":     "Import-Export"}

"""
Usage Notes:

This export script is still under development.

Copyright 2013 Don Viszneki <don@codebad.com> all rights reserved.

"""
import bpy
from bpy_extras.io_utils import ExportHelper

def getDiffuseColorString(mat):
    c = mat.diffuse_color
    return '%f %f %f' % (c.r, c.g, c.b)

def escherExport(materials, objects, scene, filename):
    spaces = []
    for obj in objects:
        if obj.type != 'MESH':
            continue
        me = obj.to_mesh(scene, True, 'PREVIEW', calc_tessface=False)
        spaces.append({
            'verts': me.vertices,
            'faces': me.polygons,
            'index': len(spaces)
        })

    out = open(filename, 'w')
    out.write('escher version 3\n')
    out.write('numspaces %d\n' % len(spaces))
    for si, space in enumerate(spaces):
        out.write('space %d numverts %d numfaces %d numremotes %d\n' %
                (si, len(space['verts']), len(space['faces']), 0))
        for vi, v in enumerate(space['verts']):
            out.write('vert %d %f %f %f\n' %
                (vi, v.co.x, v.co.z, v.co.y))
        for fi, f in enumerate(space['faces']):
            out.write('face %d %d %s rgb %s\n' % (
                fi, len(f.vertices), ' '.join(map(str, (f.vertices))), getDiffuseColorString(materials[f.material_index])))

class ExportEscher(bpy.types.Operator, ExportHelper):
  bl_idname       = "export.esc";
  bl_label        = "Escher Map Exporter";
  bl_options      = {'PRESET'};

  filename_ext    = ".esc";

  def execute(self, context):
    print('[escher]', context)
    for k in dir(context):
      print('  ', k)
    #escherExport(bpy.data.materials, bpy.data.objects, bpy.context.scene, filename)
    return {'FINISHED'};

def menu_func(self, context):
  self.layout.operator(ExportEscher.bl_idname, text="Escher Map (.esc)")

def register():
  bpy.utils.register_module(__name__)
  bpy.types.INFO_MT_file_export.append(menu_func)

def unregister():
  bpy.utils.unregister_module(__name__)
  bpy.types.INFO_MT_file_export.remove(menu_func)

if __name__ == "__main__":
  register()
