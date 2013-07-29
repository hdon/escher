import bpy, bmesh
from mathutils import Color

def selectedFaces(bm):
  return filter(lambda fa: fa.select, bm.faces)

def getEditMesh(cx):
  if cx.mode == 'EDIT_MESH':
      ob = cx.object
      if ob and ob.type == 'MESH' and ob.select:
        return bmesh.from_edit_mesh(ob.data)
  return None

def getPortalMaterial():
  if 'EscherPortalMaterial' in bpy.data.materials:
    return bpy.data.materials['EscherPortalMaterial']
  mat = bpy.data.materials.new('EscherPortalMaterial')
  mat.diffuse_color = Color((1,0,1))
  mat.use_transparency = True
  mat.alpha = 0.5
  return mat

class NPanel(bpy.types.Panel):
  bl_label = 'Escher'
  bl_space_type = 'VIEW_3D'
  bl_region_type = 'TOOLS'
  
  def draw(self, context):
    self.layout.operator('escher.portalize_face')
    self.layout.operator('escher.link_remote')
    self.layout.operator('escher.realize_remote')

class OBJECT_OT_HelloButton(bpy.types.Operator):
  bl_idname = "hello.hello"
  bl_label = "Say Hello"
  country = bpy.props.StringProperty()

  def execute(self, context):
    return{'FINISHED'}  
 
def getMeshMaterial(me, mat):
  '''Gets the index of a material in a mesh, and returns it.
     If it is not already a material of the mesh, it is added.'''
  if mat.name in me.materials:
    return me.materials.find(mat.name)
  rval = len(me.materials)
  me.materials.append(mat)
  return rval

class ESCHER_OT_Portalize_Face(bpy.types.Operator):
  '''Portalize selected faces'''
  bl_idname = "escher.portalize_face"
  bl_label = "Portalize Mesh Face"
  
  def execute(self, cx):
    mat = getPortalMaterial()
    me = cx.object.data
    imat = getMeshMaterial(me, mat)
    bm = getEditMesh(cx)
    if bm:
      for fa in selectedFaces(bm):
        fa.material_index = imat
    cx.object.show_transparent = True
    self.report({'INFO'}, 'Portalized face materials!')
    return {'FINISHED'}
  
  @classmethod
  def poll(cls, cx):
    me = getEditMesh(cx)
    if me:
      fa = list(selectedFaces(me))
      if len(fa):
        return True
    return False

class ESCHER_OT_LinkRemote(bpy.types.Operator):
  '''Links a remote space to this one'''
  bl_idname = "escher.link_remote"
  bl_label = "Link Remote"
  
  @classmethod
  def poll(cls, cx):
    return cx.mode == 'OBJECT' and cx.object and cx.object.type == 'MESH'

  def execute(self, cx):
    # This empty object represents the remote space
    eo = bpy.data.objects.new('EscherRemote', None)
    bpy.context.scene.objects.link(eo)
    eo.parent = cx.object
    bpy.ops.object.select_all(action='DESELECT')
    eo.select = True
    bpy.ops.transform.translate()
    return {'FINISHED'}

class ESCHER_OT_RealizeRemote(bpy.types.Operator):
  '''Creates an object parented to the symbolic EMPTY object representing an Escher Remote.
  
  The object created is referred to as an SSO, or "Secondary Space Object." This object is
  disposable and probably won't get saved in the .blend file. The PSO, or "Primary Space
  Object," is not expendable, as it has children which are important, and of course its
  data is the mesh representing the geometry of the Escher Space.'''
  
  bl_idname = 'escher.realize_remote'
  bl_label = 'Realize Remote'

  @classmethod
  def poll(cls, cx):
    return cx.mode == 'OBJECT' and cx.object and cx.object.type == 'EMPTY' and \
        'escher_remote_space_name' in cx.object

  def execute(self, cx):
    eo = cx.object
    for child in eo.children:
      if child.name.startswith('EscherSSO_'):
        self.report({'INFO'}, 'Escher Remote Space already realized!')
        return {'FINISHED'}
    remoteName = cx.object['escher_remote_space_name']
    remoteMesh = bpy.data.meshes[remoteName]
    remoteObj = bpy.data.objects.new('EscherSSO_' + remoteName, remoteMesh)
    cx.scene.objects.link(remoteObj)
    remoteObj.parent = eo
    return {'FINISHED'}

bpy.utils.register_module(__name__)
