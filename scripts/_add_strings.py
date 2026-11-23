"""把一批新文案加进 Localization.swift 的两张表。

用法：python3 scripts/_add_strings.py <json 文件>
json 格式：[["韩语键", "中文", "英文", "日文"], ...]
"""
import io
import json
import sys

BS = chr(92)


def esc(x):
    return x.replace(BS, BS + BS).replace('"', BS + '"')


def main(path):
    rows = json.load(io.open(path, encoding='utf-8'))
    p = 'Sources/PstscAgent/Localization.swift'
    s = io.open(p, encoding='utf-8').read()

    block_en = ''.join(
        '        "%s": ("%s", "%s"),\n' % (esc(k), esc(en), esc(ja))
        for k, zh, en, ja in rows)
    i = s.index('enum Translations')
    j = s.index('\n    ]', i)
    s = s[:j] + '\n' + block_en.rstrip('\n') + s[j:]

    block_zh = ''.join('        "%s": "%s",\n' % (esc(k), esc(zh)) for k, zh, en, ja in rows)
    i = s.index('enum Chinese')
    j = s.index('\n    ]', i)
    s = s[:j] + '\n' + block_zh.rstrip('\n') + s[j:]

    # newline='' 才不会在 Windows 上把 \n 写成 \r\n，否则整个文件的 diff 全变。
    with io.open(p, 'w', encoding='utf-8', newline='') as handle:
        handle.write(s)
    print("加了 %d 条" % len(rows))


if __name__ == '__main__':
    main(sys.argv[1])
