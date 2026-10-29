# 学习包格式 v1

GoodGoodStudy 接收用户自行准备的 ZIP 学习包，不转换 PDF、不执行 OCR，也不下载教材。以下短句只用于解释数据结构，是本项目编写的原创格式示例；仓库不提供教材、题库或录音资源包。

## ZIP 结构

根目录直接包含 UTF-8 JSON，不再套一层目录：

```text
manifest.json
lessons.json
entries.json
```

无音频的学习包可省略媒体目录。若加入自己的音频，请放入 `media/`，在 manifest 中声明 ID、相对路径和真实文件字节的 SHA-256；在课程中用 `audio_ref` 引用该 ID。支持的音频扩展名由导入器校验，包含 mp3/m4a/aac/wav/caf/aiff/aif。

ZIP 最大512 MiB，展开总量最大1 GiB，单文件最大128 MiB，每个JSON最大8 MiB，最多10000项。只允许普通文件和安全相对路径；绝对路径、网络地址、`..`、链接、加密或损坏条目会被拒绝。

## manifest.json

```json
{
  "schema_version": "1.0",
  "package_id": "original-window-practice",
  "content_revision": 1,
  "title": "原创格式练习",
  "language": "ja",
  "translation_language": "zh-CN",
  "level_tags": ["practice"],
  "media": []
}
```

`package_id` 为最长80字符的小写字母、数字与连字符，首位为字母或数字。更新同一资料时保持ID，增加正整数 `content_revision`，并保留已有课程、句段和词条ID，避免丢失与个人记录的关联。

## lessons.json

```json
[
  {
    "id": "practice:1",
    "title": "打开窗户",
    "topic": "日常生活",
    "entry_ids": ["word:window"],
    "segments": [
      {
        "id": "practice:1-sentence:1",
        "text": "朝は窓を開けます。",
        "translation_zh": "早上打开窗户。",
        "highlights": [{"start": 2, "end": 3, "entry_id": "word:window"}],
        "ruby": [
          {"start": 0, "end": 1, "reading": "あさ"},
          {"start": 2, "end": 3, "reading": "まど"},
          {"start": 4, "end": 5, "reading": "あ"}
        ]
      }
    ]
  }
]
```

`entry_ids` 可省略；它引用本篇全部重点词。`highlights` 引用存在的词条，`ruby` 仅呈现预先准备的读音，不自动推断。可选 `speaker` 用于对话发言人。`text` 保存原文，不嵌入 HTML，也不把假名重复写进正文。

所有 `start`／`end` 使用 UTF-16 码元，起点包含、终点不包含，与 Dart `String.substring` 相同。范围按起点排序、互不重叠，不得越界或切断代理对；`ruby` 与 `highlights` 两组范围可以相交。示例中的 `[2,3)` 正好对应「窓」。

## entries.json

```json
[
  {
    "id": "word:window",
    "surface": "窓",
    "reading": "まど",
    "meaning_zh": "窗户",
    "explanation_zh": "指建筑物的窗户。",
    "kind": "vocabulary",
    "attributes": {},
    "tags": [],
    "relations": []
  }
]
```

`kind` 为 `vocabulary` 或 `grammar`。`attributes` 的键和值均为字符串。`relations` 中的关系对象使用 `label`、`text`，以及可选的 `meaning_zh`；`source` 可保存用户自己的来源信息。

学习包只提供内容。笔记、词条个人属性、显示偏好与学习进度由应用另行保存在本机，不应作为公开资源包的一部分。个人教材的使用和分发授权由准备资料的人自行确认。
