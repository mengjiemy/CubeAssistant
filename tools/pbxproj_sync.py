#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pbxproj 文件自动注册器（魔方学院项目专用）
用法:
  python3 tools/pbxproj_sync.py <目录> [--remove-missing]
作用:
  扫描 <目录>（如 CubeAssistant/Views、CubeAssistant/Models）下的 .swift，
  把它们注册进 CubeAssistant.xcodeproj/project.pbxproj 的:
    - PBXBuildFile（生成确定性 UUID）
    - PBXFileReference
    - PBXSourcesBuildPhase Sources 段
    - 对应 group 的 children
  UUID 用 md5(文件名+group名) 取前 24 位，确定性、可重复、不冲突。
"""
import os, sys, hashlib, re

PROJ = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                    'CubeAssistant.xcodeproj', 'project.pbxproj')
SRC_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

def uuid(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()

def read(path):
    with open(path) as f: return f.read()

def write(path, s):
    with open(path, 'w') as f: f.write(s)

def ensure_added(text, added):
    for line in added:
        if line not in text:
            # 插入到 "/* Begin PBXBuildFile section */" 之后
            pass
    return text

def sync(target_dir, group_name):
    pbx = os.path.join(SRC_ROOT, 'CubeAssistant.xcodeproj', 'project.pbxproj')
    t = read(pbx)
    files = sorted(f for f in os.listdir(target_dir) if f.endswith('.swift'))
    new_build = []
    new_ref = []
    new_sources = []
    new_children = []
    for fn in files:
        bu = uuid('BF:' + group_name + '/' + fn)
        fr = uuid('FR:' + group_name + '/' + fn)
        build_line = f'\t\t{bu} /* {fn} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {fn} */; }};'
        ref_line  = f'\t\t{fr} /* {fn} */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = {fn}; sourceTree = "<group>"; }};'
        sources_line = f'\t\t\t\t{bu} /* {fn} in Sources */,'
        child_line = f'\t\t\t\t{fr} /* {fn} */,'
        if build_line not in t: new_build.append(build_line)
        if ref_line not in t: new_ref.append(ref_line)
        if sources_line not in t: new_sources.append(sources_line)
        if child_line not in t: new_children.append(child_line)
    changed = False
    if new_build:
        # 插到 PBXBuildFile section 首条目前
        marker = '/* Begin PBXBuildFile section */'
        idx = t.index(marker) + len(marker)
        t = t[:idx] + '\n' + '\n'.join(new_build) + t[idx:]
        changed = True
    if new_ref:
        marker = '/* Begin PBXFileReference section */'
        idx = t.index(marker) + len(marker)
        t = t[:idx] + '\n' + '\n'.join(new_ref) + t[idx:]
        changed = True
    if new_sources:
        # 插到 Sources phase 内（找到首个 in Sources 的行）
        m = re.search(r'(\n\t+)([A-F0-9]{24}) /\* .*? in Sources \*/,\n', t)
        if m:
            t = t[:m.start()] + '\n' + '\n'.join(new_sources) + t[m.start():]
            changed = True
    if new_children:
        # 找到对应 group 的 children，追加到末条目后
        # group 定义形如: XXXX /* {group} */ = {isa = PBXGroup; children = (\n ... \n );
        g = re.search(r'(/\* ' + re.escape(group_name) + r' \*/ = \{isa = PBXGroup; children = \(\n)(.*?)(\n\t\t\t\); \})', t, re.S)
        if g:
            t = t[:g.end(2)] + '\n' + '\n'.join(new_children) + t[g.end(2):]
            changed = True
    if changed:
        write(pbx, t)
        print(f'✅ 已更新 pbxproj，{group_name} 新增 build={len(new_build)} ref={len(new_ref)} sources={len(new_sources)} children={len(new_children)}')
    else:
        print(f'ℹ️  {group_name} 无新增，已同步')
    return new_build, new_ref

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('用法: pbxproj_sync.py <相对目录如 Views> <group名如 Views>')
        sys.exit(1)
    rel_dir, group = sys.argv[1], sys.argv[2]
    target = os.path.join(SRC_ROOT, 'CubeAssistant', rel_dir)
    if not os.path.isdir(target):
        print(f'❌ 目录不存在: {target}'); sys.exit(1)
    sync(target, group)
