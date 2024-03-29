#!/usr/bin/env python
# coding=utf-8
import sys
import gspread
from oauth2client.service_account import ServiceAccountCredentials
import json
import csv

scope = ['https://spreadsheets.google.com/feeds','https://www.googleapis.com/auth/drive']
creds = ServiceAccountCredentials.from_json_keyfile_name('client_secret.json', scope)
client = gspread.authorize(creds)
# sheet = client.open(u"統合TV番組原簿 20150701").worksheet("Pictures")
sheet = client.open(u"2020統合TV番組原簿").worksheet("Pictures")

writer = csv.writer(sys.stdout)
header = sheet.row_values(1)[0:31]
writer.writerow(header)
list_of_hashes = sheet.get_all_records()

for v in [[row[colname] for colname in header] for row in list_of_hashes]:
  writer.writerow(v)
