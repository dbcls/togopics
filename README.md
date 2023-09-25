# togopics uploader
CSV形式でデータを取得し、Wikimedia Commonsに投稿する。

## To upload to Wikidata
`togopic_wikidata.pl`を用いてWikidataに登録するためには、下記の要領で`getDataFromGspreadsheet.py`の出力するCSV形式のデータを`csv2tsv`などのツールを用いてTSVに変換し、10、26、31列の3列から成るTSVに変換した結果を`Pictures.tsv`というファイル名で保存する。

```csv2tsv 2020統合TV番組原簿-Pictures.csv | cut -f10,26,31 | sed -n '/^[[:space:]]*$/d; p' > Pictures.tsv```
