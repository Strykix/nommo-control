#!/usr/bin/env python3
"""Extrait le trafic ATT d'une capture btsnoop Android.

Sert à retrouver le protocole d'éclairage que l'application Razer Audio parle en
Bluetooth : la capture contient chaque trame échangée, y compris l'éventuelle
poignée de main que l'enceinte exige avant d'accepter une commande.

    ./scripts/parse-btsnoop.py btsnoop_hci.log            # canal Razer seul
    ./scripts/parse-btsnoop.py btsnoop_hci.log --all      # tout le trafic ATT
    ./scripts/parse-btsnoop.py btsnoop_hci.log --uuid FD65
"""

from __future__ import annotations

import argparse
import datetime as dt
import struct
import sys

# btsnoop compte les microsecondes depuis l'an 0 ; voici l'écart avec l'epoch Unix.
EPOCH_OFFSET_US = 62_168_256_000_000_000

DATALINK_H4 = 1002
ATT_CID = 0x0004

# L'UUID du canal de commande de Razer contient la chaîne ASCII « -RazerBLE ».
RAZER_SIGNATURE = "2D52-617A-6572-424C45"

ATT_WRITE_REQUEST = 0x12
ATT_WRITE_COMMAND = 0x52
ATT_NOTIFICATION = 0x1B
ATT_INDICATION = 0x1D
ATT_READ_RESPONSE = 0x0B
ATT_READ_BY_TYPE_RESPONSE = 0x09
ATT_FIND_INFORMATION_RESPONSE = 0x05

TRAFFIC_OPCODES = {
    ATT_WRITE_REQUEST: "write req",
    ATT_WRITE_COMMAND: "write cmd",
    ATT_NOTIFICATION: "notify",
    ATT_INDICATION: "indicate",
    ATT_READ_RESPONSE: "read resp",
}


def uuid_from_bytes(raw: bytes) -> str:
    """Rend un UUID 16 bits tel quel et développe un UUID 128 bits (little-endian)."""
    if len(raw) == 2:
        return f"{struct.unpack('<H', raw)[0]:04X}"
    if len(raw) == 16:
        b = raw[::-1]
        return (
            f"{b[0:4].hex().upper()}-{b[4:6].hex().upper()}-{b[6:8].hex().upper()}"
            f"-{b[8:10].hex().upper()}-{b[10:16].hex().upper()}"
        )
    return raw.hex().upper()


def read_records(path: str):
    """Produit (timestamp_us, is_from_controller, payload) pour chaque enregistrement."""
    with open(path, "rb") as handle:
        header = handle.read(16)
        if len(header) < 16 or not header.startswith(b"btsnoop\x00"):
            sys.exit(f"{path} n'est pas une capture btsnoop.")
        datalink = struct.unpack(">I", header[12:16])[0]

        while True:
            record = handle.read(24)
            if len(record) < 24:
                return
            _, included, flags, _, timestamp = struct.unpack(">IIIIq", record)
            data = handle.read(included)
            if len(data) < included:
                return
            if datalink == DATALINK_H4:
                if not data:
                    continue
                packet_type, data = data[0], data[1:]
                if packet_type != 0x02:  # on ne garde que l'ACL
                    continue
            yield timestamp, bool(flags & 0x01), data


class AclReassembler:
    """Recolle les PDU L2CAP éclatées sur plusieurs paquets ACL."""

    def __init__(self) -> None:
        self._pending: dict[tuple[int, bool], bytearray] = {}

    def feed(self, conn: int, inbound: bool, pb_flag: int, payload: bytes):
        key = (conn, inbound)
        if pb_flag == 0b01:
            buffer = self._pending.get(key)
            if buffer is None:
                return None
            buffer += payload
        else:
            buffer = bytearray(payload)
            self._pending[key] = buffer

        if len(buffer) < 4:
            return None
        length, cid = struct.unpack("<HH", buffer[:4])
        if len(buffer) < length + 4:
            return None

        del self._pending[key]
        return cid, bytes(buffer[4 : 4 + length])


class HandleMap:
    """Associe les handles d'attribut aux UUID, lus dans les réponses de découverte."""

    def __init__(self) -> None:
        self.uuids: dict[int, str] = {}

    def absorb(self, opcode: int, params: bytes) -> None:
        if opcode == ATT_READ_BY_TYPE_RESPONSE and params:
            self._absorb_read_by_type(params)
        elif opcode == ATT_FIND_INFORMATION_RESPONSE and params:
            self._absorb_find_information(params)

    def _absorb_read_by_type(self, params: bytes) -> None:
        entry_length, entries = params[0], params[1:]
        # Une déclaration de caractéristique vaut 7 octets (UUID court) ou 21 (UUID long).
        if entry_length not in (7, 21):
            return
        for offset in range(0, len(entries) - entry_length + 1, entry_length):
            entry = entries[offset : offset + entry_length]
            value_handle = struct.unpack("<H", entry[1:3])[0]
            self.uuids[value_handle] = uuid_from_bytes(entry[3:])

    def _absorb_find_information(self, params: bytes) -> None:
        fmt, entries = params[0], params[1:]
        entry_length = 4 if fmt == 0x01 else 18
        for offset in range(0, len(entries) - entry_length + 1, entry_length):
            entry = entries[offset : offset + entry_length]
            handle = struct.unpack("<H", entry[:2])[0]
            self.uuids.setdefault(handle, uuid_from_bytes(entry[2:]))

    def label(self, handle: int) -> str:
        return self.uuids.get(handle, "UUID inconnu")


def razer_report_summary(payload: bytes) -> str | None:
    """Décrit une trame si elle a la forme du rapport Razer 90 octets."""
    if len(payload) != 90:
        return None
    crc = 0
    for byte in payload[2:88]:
        crc ^= byte
    verdict = "CRC ok" if crc == payload[88] else f"CRC faux (calculé {crc:02X})"
    size = payload[5]
    return (
        f"rapport Razer : classe {payload[6]:02X} commande {payload[7]:02X} "
        f"args {payload[8 : 8 + size].hex(' ').upper()} — {verdict}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("capture", help="fichier btsnoop_hci.log")
    parser.add_argument("--all", action="store_true", help="afficher tout le trafic ATT")
    parser.add_argument("--uuid", help="ne garder que les UUID contenant ce fragment")
    args = parser.parse_args()

    reassembler = AclReassembler()
    handles = HandleMap()
    rows: list[tuple[int, str, int, str, bytes]] = []

    for timestamp, inbound, data in read_records(args.capture):
        if len(data) < 4:
            continue
        header, length = struct.unpack("<HH", data[:4])
        conn, pb_flag = header & 0x0FFF, (header >> 12) & 0x03
        result = reassembler.feed(conn, inbound, pb_flag, data[4 : 4 + length])
        if result is None:
            continue
        cid, pdu = result
        if cid != ATT_CID or not pdu:
            continue

        opcode, params = pdu[0], pdu[1:]
        handles.absorb(opcode, params)
        if opcode in TRAFFIC_OPCODES and len(params) >= 2:
            handle = struct.unpack("<H", params[:2])[0]
            rows.append((timestamp, TRAFFIC_OPCODES[opcode], handle, "<-" if inbound else "->", params[2:]))

    if handles.uuids:
        print("Handles découverts")
        for handle in sorted(handles.uuids):
            print(f"  0x{handle:04X}  {handles.uuids[handle]}")
        print()

    if args.uuid:
        wanted = args.uuid.upper()
    elif args.all:
        wanted = None
    else:
        wanted = RAZER_SIGNATURE

    shown = 0
    print("Trafic ATT  (-> vers l'appareil, <- depuis l'appareil)")
    for timestamp, kind, handle, direction, payload in rows:
        uuid = handles.label(handle)
        if wanted and wanted not in uuid.upper():
            continue
        moment = dt.datetime.fromtimestamp((timestamp - EPOCH_OFFSET_US) / 1e6)
        print(f"  {moment:%H:%M:%S.%f}"[:-3] + f" {direction} {kind:<9} 0x{handle:04X} {uuid}")
        print(f"      {payload.hex(' ').upper()}")
        summary = razer_report_summary(payload)
        if summary:
            print(f"      {summary}")
        shown += 1

    if not shown:
        hint = "aucun trafic ATT dans la capture" if not rows else "aucune trame ne correspond au filtre"
        print(f"  ({hint} — relancez avec --all pour tout voir)")


if __name__ == "__main__":
    main()
