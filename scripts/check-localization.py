#!/usr/bin/env python3
"""本地化表冒烟检查。

0.2.2 的中文界面一打开连接窗口就崩，原因是 Localization.swift 里
`Chinese.table` 出现了重复键——Swift 初始化字典字面量时直接 trap，
而这张表是 lazy 的，所以只有中文用户会撞上。

Swift 编译器不报重复键，这里补上：扫两张表，报重复键和两张表不一致。
退出码非 0 表示有问题，build-app.sh 会因此中止。
"""
import io
import sys
import collections

PATH = "Sources/PstscAgent/Localization.swift"


def key_of(line):
    s = line.strip()
    if not s.startswith('"'):
        return None
    i = 1
    while i < len(s):
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == '"':
            break
        i += 1
    if i >= len(s):
        return None
    if not s[i + 1:].lstrip().startswith(":"):
        return None
    return s[1:i]


def scan(src, marker, label):
    start = src.index(marker)
    # 表体从 table 声明后的第一个 "[" 开始，到同一缩进层级的 "]" 结束。
    start = src.index("= [", start)
    end = src.index("\n    ]", start)
    offset = src[:start].count("\n")
    keys, lines = [], []
    for n, line in enumerate(src[start:end].split("\n")):
        k = key_of(line)
        if k is not None:
            keys.append(k)
            lines.append(offset + n + 1)
    dup = {k: c for k, c in collections.Counter(keys).items() if c > 1}
    problems = []
    for k in dup:
        where = [ln for kk, ln in zip(keys, lines) if kk == k]
        problems.append(f"{label}: 重复键 {k!r} @ 行 {where}")
    return set(keys), problems


def main():
    src = io.open(PATH, encoding="utf-8").read()
    en, problems = scan(src, "enum Translations", "Translations(en/ja)")
    zh, more = scan(src, "enum Chinese", "Chinese")
    problems += more
    for k in sorted(zh - en):
        problems.append(f"Chinese 有 / en-ja 无: {k!r}")
    for k in sorted(en - zh):
        problems.append(f"en-ja 有 / Chinese 无: {k!r}")

    if problems:
        print(f"本地化检查失败（{len(problems)} 项）:", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1
    print(f"本地化检查通过：{len(en)} 个键，两张表一致，无重复")
    return 0


if __name__ == "__main__":
    sys.exit(main())
