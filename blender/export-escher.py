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
from bpy.props import StringProperty
from collections import OrderedDict
from os.path import basename

def getDiffuseColorString(mat):
    c = mat.diffuse_color
    return '%f %f %f' % (c.r, c.g, c.b)

def emitVert(v, uv):
  return '%f %f %f %f %f' % (v.x, v.y, v.z, uv.x, uv.y)

def unlocalizeMaterialIndex(mats, me, mai):
  return me.materials[mai]

class SuperMap:
  def __init__(self):
    self.keys = []
    self.values = {}
  def __getitem__(self, k): 
    if type(k) is str:
      return self.values[k]
    else:
      return self.values[self.keys[k]]
  def __setitem__(self, k, v): 
    if type(k) is not str:
      raise TypeError('Invalid key type')
    self.keys.append(k)
    self.values[k] = v 
  def __iter__(self):
    return SuperMapIterator(self)
  def __len__(self):
    return len(self.keys)
  def str2int(self, k):
    return self.keys.index(k)

class SuperMapIterator:
  def __init__(self, supermap):
    self.supermap = supermap
    self.n = 0 
  def __next__(self):
    n = self.n
    if n >= len(self.supermap):
      raise StopIteration()
    self.n += 1
    return self.supermap[n]

def texSlot2texMapType(s):
  # TODO TODO TODO TODO TODO
  if s.use_map_color_diffuse:
    return 'COLOR'
  if s.use_map_normal:
    return 'NORMAL'
  return 'NONE'

def escherExport(materials, objects, scene, filename):
  mats = SuperMap()
  for mat in materials:
    if not mat.name.startswith('EscherPortalMaterial'):
      mats[mat.name] = mat

  PSOs = SuperMap()
  # TODO enumerate scene.objects instead? might be faster
  for ob in objects:
    if ob.name.startswith('EscherPSO_'):
      if ob.type != 'MESH':
        raise Exception('PSO type is not MESH')
      PSOs[ob.name] = ob

  out = open(filename, 'w')
  out.write('escher version 4\n')
  out.write('nummaterials %d\n' % len(mats))

  for imat, mat in enumerate(mats):
    texSlots = list(filter(lambda t:t is not None, mat.texture_slots))
    out.write('material %d "%s" numtex %d\n' % (imat, mat.name, len(texSlots)))
    for texSlot in texSlots:
      texMapType = texSlot2texMapType(texSlot)
      textureFilePath = mat.texture_slots[0].texture.image.filepath
      out.write('texture %s %s\n' % (texMapType, basename(textureFilePath)))

  for iPSO, PSO in enumerate(PSOs):
    me = PSO.data
    remotes = list(filter(lambda o:o.name.startswith('EscherRemote'), PSO.children))
    # Write "space" command
    out.write('space %d numverts %d numfaces %d numremotes %d\n' %
      (iPSO, len(me.vertices), len(me.polygons), len(remotes)))
    # Write "vert" commands
    for vi, v in enumerate(me.vertices):
      out.write('vert %d %f %f %f\n' %
        (vi, v.co.x, v.co.z, v.co.y))
    # Write "face" commands
    # TODO multiple UV layers
    UVs = me.uv_layers[0]
    for ipg, pg, in enumerate(me.polygons):
      mat = mats.str2int(PSO.material_slots[pg.material_index].material.name)
      out.write('face %d mat %d indices %d' % (ipg, mat, pg.loop_total))
      for li in pg.loop_indices:
        vi = me.loops[li].vertex_index
        out.write(' %d' % vi)
        for uvlayer in me.uv_layers:
          uv = uvlayer.data[li].uv
          out.write(' %f %f' % (uv.x, uv.y))
      out.write('\n')
  out.close()

class ExportEscher(bpy.types.Operator, ExportHelper):
  bl_idname       = "export.esc";
  bl_label        = "Escher Map Exporter";
  bl_options      = {'PRESET'};

  filename_ext    = ".esc4";
  filter_glob = StringProperty(default="*.esc4", options={'HIDDEN'})

  filepath = bpy.props.StringProperty(
      name="File Path", 
      description="Output file path", 
      maxlen=1024, default="")

  def execute(self, context):
    print('exporting esc4 to filename "%s"' % self.properties.filepath)
    escherExport(bpy.data.materials, bpy.data.objects, bpy.context.scene, self.properties.filepath)
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
