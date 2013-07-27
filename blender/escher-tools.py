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

class ObjectPanel(bpy.types.Panel):
  bl_label = "Escher (Object)"
  bl_space_type = "PROPERTIES"
  bl_region_type = "WINDOW"
  bl_context = "object"
 
  def draw(self, context):
    self.layout.operator("hello.hello", text='Bonjour').country = "France"
    self.layout.operator("escher.portalize_face")

class MaterialPanel(bpy.types.Panel):
  bl_label = "Escher (Material)"
  bl_space_type = "PROPERTIES"
  bl_region_type = "WINDOW"
  bl_context = "material"
 
  def draw(self, context):
    self.layout.operator("hello.hello", text='Ciao').country = "Italy"
 
class OBJECT_OT_HelloButton(bpy.types.Operator):
  bl_idname = "hello.hello"
  bl_label = "Say Hello"
  country = bpy.props.StringProperty()

  def execute(self, context):
    return{'FINISHED'}  
 
class ESCHER_OT_Portalize_Face(bpy.types.Operator):
  '''Portalize selected faces'''
  bl_idname = "escher.portalize_face"
  bl_label = "Portalize Mesh Face"
  
  def execute(self, context):
    print(getPortalMaterial())
    return {'FINISHED'}
  
  @classmethod
  def poll(cls, cx):
    me = getEditMesh(cx)
    if me:
      print('found active mesh')
      fa = list(selectedFaces(me))
      if len(fa):
        return True
    return False

bpy.utils.register_module(__name__)
