import json

def parse_cube():
    with open('cube.gltf', 'r') as f:
        gltf = json.load(f)

    meshes = gltf['meshes']
    assert len(meshes) == 1

    mesh = gltf['meshes'][0]
    primitives = mesh['primitives']
    assert len(primitives) == 1

    primitive = primitives[0]
    attributes = primitive['attributes']
    position_idx = attributes['POSITION']

    accessors = gltf['accessors']
    position = accessors[position_idx]
    assert position['componentType'] == 5126 # float
    assert position['type'] == 'VEC3'

    position_buf_view_idx = position['bufferView']
    position_buf_view = gltf['bufferViews'][position_buf_view_idx]
    
    position_byte_length = position_buf_view['byteLength']
    position_byte_offset = position_buf_view['byteOffset']
    assert position_buf_view['target'] == 34962 # array buffer

    uri = gltf['buffers'][position_buf_view_idx]['uri']
    with open(uri, 'rb') as in_file, \
         open('positions.bin', 'wb') as output:
        in_file.seek(position_byte_offset, 0)
        data = in_file.read(position_byte_length)
        output.write(data)

    print('done')

if __name__ == '__main__':
    parse_cube()
