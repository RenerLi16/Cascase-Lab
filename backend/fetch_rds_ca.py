"""Download Amazon RDS's public CA bundle so the database connection can be fully verified.

Run at build time on the host (Render): python3 -m backend.fetch_rds_ca
Source documented at https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html
"""
from pathlib import Path
import urllib.request

URL = 'https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem'
TARGET = Path(__file__).resolve().parent / 'certs' / 'rds-global-bundle.pem'


def main():
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(URL, timeout=30) as response:
        data = response.read(2_000_000)
    if data.count(b'-----BEGIN CERTIFICATE-----') < 1:
        raise SystemExit('Downloaded RDS CA bundle is not a certificate bundle')
    TARGET.write_bytes(data)
    print(f'RDS CA bundle saved ({data.count(b"BEGIN CERTIFICATE")} certificates)')


if __name__ == '__main__':
    main()
