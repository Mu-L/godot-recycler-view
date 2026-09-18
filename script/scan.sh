#!/bin/bash
#
# 校验 .gdextension 描述符与实际库文件是否一致:
#   1. [libraries] 里声明的每个文件都存在;
#   2. 平台目录下没有"存在但未声明"的库文件(它们会被打进发布包,却永远不会被加载)。
#
# 用法:
#   script/scan.sh [描述符路径]
#   默认 project/bin/godot_recycler_view.gdextension,从仓库根目录运行。
#
# 退出码:
#   0 = 一致
#   1 = 有漂移(缺失或多余),CI 应当据此失败
#   2 = 用法错误(描述符不存在)
#
# 兼容 macOS 自带的 bash 3.2:不用 mapfile,也不用关联数组。
# 关键点是所有读数组的循环都走进程替换而非管道 —— 管道会开子 shell,
# 循环里的赋值出不来,这正是这脚本原先"永远报告一切正常"的原因。

set -euo pipefail

DEFAULT_DESCRIPTOR="project/bin/godot_recycler_view.gdextension"
GDEXTENSION_FILE="${1:-$DEFAULT_DESCRIPTOR}"

if [[ ! -f "$GDEXTENSION_FILE" ]]; then
    echo "错误: 未找到描述符 $GDEXTENSION_FILE" >&2
    echo "提示: 从仓库根目录运行,或显式传入路径。" >&2
    exit 2
fi

# 描述符里的路径是相对它自己所在目录的。
DESCRIPTOR_DIR=$(cd "$(dirname "$GDEXTENSION_FILE")" && pwd)
DESCRIPTOR_NAME=$(basename "$GDEXTENSION_FILE")

echo "正在检查 $GDEXTENSION_FILE ..."

# 数组里是否含有某个元素。
contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# --- 1. 解析声明路径 ---------------------------------------------------------
# 注释以 ';' 开头(Godot ini 风格),也容忍 '#';空行跳过。
LISTED_PATHS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && LISTED_PATHS+=("$line")
done < <(
    awk '
        /^\[/ { in_libs = ($0 ~ /^\[libraries\]/) ; next }
        in_libs && NF > 0 && $0 !~ /^[[:space:]]*[;#]/ { print }
    ' "$GDEXTENSION_FILE" |
    while IFS='=' read -r _key value; do
        path="${value#"${value%%[![:space:]]*}"}"   # 去前导空白
        path="${path%"${path##*[![:space:]]}"}"     # 去尾随空白
        path="${path%\"}"; path="${path#\"}"        # 去引号
        path="${path#./}"                           # 去开头 ./
        [[ -n "$path" ]] && printf '%s\n' "$path"
    done
)

if [[ ${#LISTED_PATHS[@]} -eq 0 ]]; then
    echo "错误: $DESCRIPTOR_NAME 的 [libraries] 段是空的。" >&2
    exit 1
fi

echo "  声明了 ${#LISTED_PATHS[@]} 个库文件。"

LIB_FIND=( -type f \( -name "*.dylib" -o -name "*.so" -o -name "*.dll" -o -name "*.wasm" \) )

# --- 2. 缺失检查 -------------------------------------------------------------
MISSING=0
for p in "${LISTED_PATHS[@]}"; do
    if [[ ! -f "$DESCRIPTOR_DIR/$p" ]]; then
        echo "❌ 声明了但不存在: $p"
        MISSING=1
    fi
done

# --- 3. 多余检查 -------------------------------------------------------------
# 只扫描"声明过的目录":完全没有被声明的平台目录另行处理(见下)。
SCANNED_DIRS=()
EXTRA=0
for p in "${LISTED_PATHS[@]}"; do
    dir="${p%/*}"
    [[ "$dir" == "$p" ]] && dir="."              # 没有斜杠 = 描述符同目录
    contains "$dir" ${SCANNED_DIRS[@]+"${SCANNED_DIRS[@]}"} && continue
    SCANNED_DIRS+=("$dir")
    [[ -d "$DESCRIPTOR_DIR/$dir" ]] || continue

    while IFS= read -r file; do
        rel="${file#"$DESCRIPTOR_DIR"/}"
        rel="${rel#./}"
        if ! contains "$rel" "${LISTED_PATHS[@]}"; then
            echo "⚠️  存在但未声明: $rel"
            EXTRA=1
        fi
    done < <(find "$DESCRIPTOR_DIR/$dir" -maxdepth 1 "${LIB_FIND[@]}" | sort)
done

# 整个目录都没被声明的情况:里面有库文件才报。
for d in "$DESCRIPTOR_DIR"/*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "$d")
    declared=0
    for p in "${LISTED_PATHS[@]}"; do
        [[ "${p%/*}" == "$name" ]] && { declared=1; break; }
    done
    [[ $declared -eq 1 ]] && continue
    found=$(find "$d" -maxdepth 1 "${LIB_FIND[@]}" | sort | head -1)
    if [[ -n "$found" ]]; then
        echo "⚠️  目录 '$name/' 下的库文件未被声明: ${found#"$DESCRIPTOR_DIR"/}"
        EXTRA=1
    fi
done

# --- 4. 结论 -----------------------------------------------------------------
if [[ $MISSING -eq 0 && $EXTRA -eq 0 ]]; then
    echo "✅ 描述符与实际库文件一致。"
    exit 0
fi

[[ $MISSING -eq 1 ]] && echo "→ 有文件被声明但缺失:构建矩阵与描述符不同步?"
[[ $EXTRA -eq 1 ]]   && echo "→ 有库文件未被声明:它们不会被打包加载。"
exit 1
