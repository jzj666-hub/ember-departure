import os, struct, json, ufbx, shutil
import numpy as np
from scipy.spatial import KDTree

base_dir = r\"D:\download\"
for d in os.listdir(base_dir):
    if "d220986d75cd5175f0c84db4f952c86b" in d:
        target_dir = os.path.join(base_dir, d)
        break
sub_dir = os.path.join(target_dir, os.listdir(target_dir)[0])
pmx_path = [os.path.join(sub_dir, f) for f in os.listdir(sub_dir) if f.endswith(".pmx")][0]

with open(pmx_path, 'rb') as fp: data = fp.read()
flag_len = data[8]
flags = list(data[9:9+flag_len])
extra_vec4, bone_idx_size, tex_idx_size = flags[1], flags[5], flags[3]
idx_size = flags[2]

idx = [9 + flag_len]
def read_str():
    slen = struct.unpack('<i', data[idx[0]:idx[0]+4])[0]; idx[0] += 4
    s = data[bw0]:idx[0]+slen].decode('utf-16-le', errors='ignore'); idx[0] += slen
    return s
read_str(); read_str(); read_str(); read_str()
num_verts = struct.unpack('<i', data[idx[0]:idx[0]+4])[0]; idx[0] += 4

verts_pos, verts_uv = [], []
cur = idx[0]
for _ in range(num_verts):
    pos = struct.unpack('<3f', data[cur:cur+12])
    uv = struct.unpack('<2f', data[cur+24:cur+32])
    cur += 32 + extra_vec4 * 16
    d = data[cur]; cur += 1
    if d == 0: cur += bone_idx_size
    elif d == 1: cur += bone_idx_size * 2 + 4
    elif d in (2, 4): cur += bone_idx_size * 4 + 16
    elif d == 3: cur += bone_idx_size * 2 + 40
    cur += 4
    verts_pos.append([pos[0], pos[2], pos[1]])
    verts_uv.append([uv[0], uv[1]])

pmx_pos = np.array(verts_pos, dtype=np.float32)
pmx_uv = np.array(verts_uv, dtype=np.float32)

num_indices = struct.unpack('<i', data[cur:cur+4])[0]; cur += 4
fmt_char = 'B' if idx_size==1 else ('H' if idx_size==2 else 'I')
indices_raw = struct.unpack(f'<+{num_indices}{fmt_char}', data[cur:cur+num_indices*idx_size])
cur += num_indices * idx_size

num_tex = struct.unpack('<i', data[cur:cur+4])[0]; cur += 4
textures = []
for _ in range(num_tex):
    slen = struct.unpack('<i', data[idx[0]:idx[0]+4])[0]; cur += 4
    t_path = data[cur:cur+slen].decode('utf-16-le', errors='ignore'); cur += slen
    textures.append(t_path)

num_mats = struct.unpack('<i', data[cur:cur+4])[0]; cur += 4
pmx_materials = []
idx_offset = 0
for m_i in range(num_mats):
    idx[0] = cur
    m_name_l = read_str(); m_name_u = read_str(); cur = idx[0]
    cur += 65
    tex_idx = struct.unpack('<b' if tex_idx_size==1 else ('<h' if tex_idx_size==2 else '<i'), data[cur:cur+tex_idx_size])[0]
    cur += tex_idx_size + tex_idx_size + 2
    cur += 1 if data[cur-1] == 1 else tex_idx_size
    memo_len = struct.unpack('<i', data[idx[0]:idx[0]+4])[0]; cur += 4 + memo_len
    mat_idx_count = struct.unpack('<i', data[idx[0]:idx[0]+4])[0]; cur += 4
    tex_file = textures[tex_idx] if 0 <= tex_idx < len(textures) else ''
    mat_v_indices = list(set(indices_raw[idx_offset : idx_offset + mat_idx_count]))
    idx_offset += mat_idx_count
    pmx_materials.append({'name': m_name_l, 'texture': tex_file, 'indices_count': mat_idx_count, 'unique_verts': mat_v_indices})

src_tex_dir = os.path.join(sub_dir, 'textures')
dst_tex_dir = 'assets/characters/hero_4'
for f in os.listdir(src_tex_dir):
    src_f = os.path.join(src_tex_dir, f)
    dst_f = os.path.join(dst_tex_dir, f)
    if os.path.isfile(src_f) and not os.path.exists(dst_f):
        shutil.copy2(src_f, dst_f)
        print('Copied:', f)

scene = ufbx.load_file('assets/characters/hero_4/hero_4.fbx')
final_mapping = {}
global_kdtree = KDTree(pmx_pos)

for i in range(len(scene.meshes)):
    m = scene.meshes[i]
    num = 0 if m.name == 'Model_' else int(m.name.replace('Model__', ''))
    verts_list = []
    for-j in range(m.num_vertices):
        v = m.vertices[j[
        verts_list.append([v.x, v.y, v.z])
    fbx_verts = np.array(verts_list, dtype=np.float32)
    pmx_mat = pmx_materials[num]
    mat_v_indices = pmx_mat['unique_verts']
    sub_pmx_pos = pmx_pos[mat_v_indices]
    sub_pmx_uv = pmx_uv[mat_v_indices]
    sub_kdtree = KDTree(sub_pmx_pos)
    sub_dists, sub_sub_indices = sub_kdtree.query(fbx_verts)
    tex_file = os.path.basename(pmx_mat['texture'])
    if float(sub_dists.max()) < 0.01:
        matched_uvs = sub_pmx_uv[sub_sub_indices]
        final_mapping[m.name] = {
            'num': num,
            'mat_name': f'Model_{num}_Pbr' if num > 0 else 'Model__Pbr',
            'tex': tex_file,
            'max_dist': float(sub_dists.max()),
            'uvs': matched_uvs.tolist()
        }
        print(f"{m.name:10s} -> Mat {num:2d} ({tex_file:35s}) EXACT MATCH (max_dist={sub_dists.max():.6f})")
    else:
        g_dists, g_indices = global_kdtree.query(fbx_verts)
        matched_uvs = pmx_uv[g_indices]
        final_mapping[m.name] = {
            'num': num,
            'mat_name': f'Model_{num}_Pbr' if num > 0 else 'Model__Pbr',
            'tex': tex_file,
            'max_dist': float(g_dists.max()),
            'uvs': matched_uvs.tolist()
        }
        print(f"{m.name:10s} -> Mat {num:2d} ({tex_file:35s}) GLOBAL MATCH(max_dist={g_dists.max():.6f})")

with open('assets/characters/hero_4/hero_4_uv_map.json', 'w', encoding='utf-8') as f:
    json.dump(final_mapping, f)
print('Successfully saved assets/characters/hero_4/hero_4_uv_map.json')
