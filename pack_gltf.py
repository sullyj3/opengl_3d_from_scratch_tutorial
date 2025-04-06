import json
from enum import Enum, StrEnum

class ComponentType(Enum):
    UNSIGNED_SHORT = 5123
    FLOAT = 5126

class AccessorType(StrEnum):
    SCALAR = 'SCALAR'
    VEC3 = 'VEC3'

class BufferViewTarget(Enum):
    ARRAY_BUFFER = 34962
    ELEMENT_ARRAY_BUFFER = 34963

def dump_accessor(
        gltf,
        accessor_idx,
        output_path,
        expected_component_type: ComponentType,
        expected_type: AccessorType,
        expected_target: BufferViewTarget):

    accessor = gltf['accessors'][accessor_idx]
    assert accessor['componentType'] == expected_component_type.value
    assert accessor['type'] == expected_type

    buf_view_idx = accessor['bufferView']
    buf_View = gltf['bufferViews'][buf_view_idx]
    
    byte_length = buf_View['byteLength']
    byte_offset = buf_View['byteOffset']
    assert buf_View['target'] == expected_target.value

    buf_idx = buf_View['buffer']
    uri = gltf['buffers'][buf_idx]['uri']

    with open(uri, 'rb') as in_file, \
         open(output_path, 'wb') as output:
        in_file.seek(byte_offset, 0)
        data = in_file.read(byte_length)
        bytes_written = output.write(data)
        assert(bytes_written == byte_length)
        print(f"wrote {bytes_written} bytes to {output_path}")

def parse_dump_cube():
    with open('cube.gltf', 'r') as f:
        gltf = json.load(f)

    meshes = gltf['meshes']
    assert len(meshes) == 1

    mesh = gltf['meshes'][0]
    primitives = mesh['primitives']
    assert len(primitives) == 1

    primitive = primitives[0]

    dump_accessor(
            gltf,
            primitive['attributes']['POSITION'],
            'positions.bin',
            ComponentType.FLOAT,
            AccessorType.VEC3,
            BufferViewTarget.ARRAY_BUFFER)

    dump_accessor(
            gltf,
            primitive['indices'],
            'indices.bin',
            ComponentType.UNSIGNED_SHORT,
            AccessorType.SCALAR,
            BufferViewTarget.ELEMENT_ARRAY_BUFFER)

if __name__ == '__main__':
    parse_cube()
