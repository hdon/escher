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

def getMeshFromObject(sc, ob, modSettings):
  '''Get a mesh with modifiers and ob.matrix_world transform applied.
  Be sure to remove when finished with bpy.data.meshes.remove(me).
  Arguments: Scene, Object, Modifier setting (PREVIEW or RENDER)'''
  me = ob.to_mesh(sc, True, 'PREVIEW', True, False)
  me.transform(ob.matrix_world)
  return me

# These functions were taken from escher-tools.py
# TODO put common functions in a common module somewhere
#      Or maybe merge this module with the other one
def portalMaterialName2remoteIndex(matName):
  if not isPortalMaterialName(matName):
    raise ValueError('Invalid Escher Portal Material name')
  s = matName[20:]
  if len(s):
    return int(s)
  return 0

def isPortalMaterialName(matName):
  return matName.startswith('EscherPortalMaterial')

def isUnqualifiedSpaceName(spaceName):
  return not (spaceName.startswith('EscherPSO_') or spaceName.startswith('EscherSSO_') or spaceName.startswith('EscherSM_'))

def unqualifyObName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return spaceName
  return spaceName[spaceName.find('_')+1:]

def spaceName2meshName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return 'EscherSM_' + spaceName
  raise ValueError('Invalid space name!')

def spaceName2psoName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return 'EscherPSO_' + spaceName
  raise ValueError('Invalid space name!')

def spaceName2ssoName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return 'EscherSSO_' + spaceName
  raise ValueError('Invalid space name!')

def classifyObName(spaceName):
  "Returns a string describing the type of special Escher Object the name came from."
  if spaceName.startswith('EscherPSO_'):
    return 'PSO'
  if spaceName.startswith('EscherSSO_'):
    return 'SSO'
  if spaceName.startswith('EscherPathO_'):
    return 'PATH'
  if spaceName.startswith('EscherSpawnO_'):
    return 'SPAWN'
  return 'UNQUALIFIED'

def isPathName(obName):
  return classifyObName(obName) == 'PATH'

def objectIsRemote(o):
  return o.type == 'EMPTY' and o.name.startswith('EscherRemote')

def objectIsSpawn(o):
  return o.type == 'EMPTY' and not o.name.startswith('EscherRemote') and o.escherSpawn

def vec3toStr(v):
  return '%s %s %s' % (repr(-v.x), repr(v.z), repr(v.y))

def euler2str(v):
  return '%s %s %s' % (repr(v.x), repr(v.z), repr(v.y))

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
    obClass = classifyObName(ob.name)
    if obClass == 'PSO':
      if ob.type != 'MESH':
        raise Exception('PSO type is not MESH')
      PSOs[unqualifyObName(ob.name)] = ob

  out = open(filename, 'w')
  out.write('escher version 6\n')
  out.write('nummaterials %d\n' % len(mats))

  for imat, mat in enumerate(mats):
    texSlots = list(filter(lambda t:t is not None, mat.texture_slots))
    out.write('material %d "%s" numtex %d\n' % (imat, mat.name, len(texSlots)))
    for iTexSlot, texSlot in enumerate(texSlots):
      texMapType = texSlot2texMapType(texSlot)
      textureFilePath = mat.texture_slots[iTexSlot].texture.image.filepath
      out.write('texture %s %s\n' % (texMapType, basename(textureFilePath)))

  out.write('numspaces %d\n' % len(PSOs))
  for iPSO, PSO in enumerate(PSOs):
    me = PSO.data
    remotes = list(filter(objectIsRemote, PSO.children))
    spawns = list(filter(objectIsSpawn, PSO.children))
    # Write "space" command
    out.write('space %d numverts %d numfaces %d numremotes %d numspawns %d\n' %
      (iPSO, len(me.vertices), len(me.polygons), len(remotes), len(spawns)))
    # Write "remote" commands
    for iRemote, remote in enumerate(remotes):
      remoteSpaceName = remote['escher_remote_space_name']
      if remoteSpaceName == '*none*':
        remoteIndex = -1
      else:
        remoteIndex = PSOs.str2int(remoteSpaceName)
      translation = vec3toStr(remote.location)
      orientation = euler2str(remote.rotation_euler)
      out.write('remote %d space %d translation %s orientation %s\n' % (iRemote, remoteIndex, translation, orientation))
    # Write "spawn" commands
    for iSpawn, spawn in enumerate(spawns):
      spawnType = spawn.escherSpawn
      translation = vec3toStr(spawn.location)
      orientation = euler2str(spawn.rotation_euler)
      # Does this spawner have a path for its entity to follow?
      spawnerPaths = list(filter(lambda ob:isPathName(ob.name), spawn.children))
      spawnerPathParam = ''
      if len(spawnerPaths) > 1:
        raise Exception('multiple paths per spawner not supported!')
      elif len(spawnerPaths) == 1:
        try:
          # Grab path mesh
          pathMe = getMeshFromObject(scene, spawnerPaths[0], 'PREVIEW')
          if len(pathMe.polygons) != 1:
            raise Exception('spawner path has %d faces, only 1 is supported' % len(pathMe).polgons)
          spawnerPathParam = ' path'
          for v in pathMe.polygons[0].vertices:
            spawnerPathParam += ' ' + vec3toStr(pathMe.vertices[v].co)
        finally:
          bpy.data.meshes.remove(pathMe)
      out.write('spawn %d translation %s orientation %s params %s%s\n' %
        (iSpawn, translation, orientation, spawnType, spawnerPathParam))
    # Write "vert" commands
    for vi, v in enumerate(me.vertices):
      out.write('vert %d %f %f %f\n' %
        (vi, -v.co.x, v.co.z, v.co.y))
    # Write "face" commands
    for ipg, pg, in enumerate(me.polygons):
      matName = PSO.material_slots[pg.material_index].material.name
      if isPortalMaterialName(matName):
        faceClass = 'remote %d' % portalMaterialName2remoteIndex(matName)
      else:
        faceClass = 'mat %d' % mats.str2int(matName)
      out.write('face %d %s vdata %d' % (ipg, faceClass, pg.loop_total))
      for li in pg.loop_indices:
        vi = me.loops[li].vertex_index
        # Write vertex index
        out.write(' %d' % vi)
        # Write vertex UVs
        for uvlayer in me.uv_layers:
          uv = -uvlayer.data[li].uv
          out.write(' %f %f' % (uv.x, uv.y))
        # Write normals
        if pg.use_smooth:
          normal = me.vertices[vi].normal
        else:
          normal = pg.normal
        out.write(' %f %f %f' % (-normal.x, normal.z, normal.y))
      out.write('\n')
  out.close()

class ExportEscher(bpy.types.Operator, ExportHelper):
  bl_idname       = "export.esc";
  bl_label        = "Escher Map Exporter";
  bl_options      = {'PRESET'};

  filename_ext    = ".esc6";
  filter_glob = StringProperty(default="*.esc6", options={'HIDDEN'})

  filepath = bpy.props.StringProperty(
      name="File Path", 
      description="Output file path", 
      maxlen=1024, default="")

  def execute(self, context):
    print('exporting esc6 to filename "%s"' % self.properties.filepath)
    escherExport(bpy.data.materials, bpy.data.objects, bpy.context.scene, self.properties.filepath)
    return {'FINISHED'};

def menu_func(self, context):
  self.layout.operator(ExportEscher.bl_idname, text="Escher Map (.esc6)")

def register():
  bpy.utils.register_module(__name__)
  bpy.types.INFO_MT_file_export.append(menu_func)
  bpy.types.Object.escherSpawn = bpy.props.StringProperty()

def unregister():
  bpy.utils.unregister_module(__name__)
  bpy.types.INFO_MT_file_export.remove(menu_func)
  del bpy.types.Object.escherSpawn

if __name__ == "__main__":
  register()
