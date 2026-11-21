"""HMG-API mod signer (same output as hmgapi.engine.Signing sign): python3 -I sign.py <mod dir> <pem key>.
manifest.json = {"format":1,"id","version","uuid","key","files":{path: sha256}} (files sorted, META-HMGAPI excluded),
signature = base64(DER ECDSA P-256 SHA-256 over manifest.json bytes). uuid: sha256(pub DER)[:16], byte6=(b&0x0f)|0x80,
byte8=(b&0x3f)|0x80 (Signing.uuid). Also verifies what it wrote."""
import base64, hashlib, json, os, sys
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

mod, keyf = sys.argv[1], sys.argv[2]
priv = serialization.load_pem_private_key(open(keyf, 'rb').read(), None)
pub = priv.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
h = bytearray(hashlib.sha256(pub).digest())
h[6] = (h[6] & 0x0f) | 0x80
h[8] = (h[8] & 0x3f) | 0x80
x = h[:16].hex()
uuid = '-'.join([x[0:8], x[8:12], x[12:16], x[16:20], x[20:32]])
mj = json.load(open(os.path.join(mod, 'mod.json')))
files = {}
for root, dirs, names in os.walk(mod):
    for n in names:
        p = os.path.relpath(os.path.join(root, n), mod).replace(os.sep, '/')
        if p.startswith('META-HMGAPI/') or n == '.DS_Store':
            continue
        files[p] = hashlib.sha256(open(os.path.join(root, n), 'rb').read()).hexdigest()
man = {"format": 1, "id": mj["id"], "version": mj["version"], "uuid": uuid,
       "key": base64.b64encode(pub).decode(), "files": dict(sorted(files.items()))}
b = json.dumps(man, indent=2).encode('utf-8')
sig = priv.sign(b, ec.ECDSA(hashes.SHA256()))
os.makedirs(os.path.join(mod, 'META-HMGAPI'), exist_ok=True)
open(os.path.join(mod, 'META-HMGAPI', 'manifest.json'), 'wb').write(b)
open(os.path.join(mod, 'META-HMGAPI', 'signature'), 'w').write(base64.b64encode(sig).decode() + '\n')
# verify back
b2 = open(os.path.join(mod, 'META-HMGAPI', 'manifest.json'), 'rb').read()
s2 = base64.b64decode(open(os.path.join(mod, 'META-HMGAPI', 'signature')).read().strip())
priv.public_key().verify(s2, b2, ec.ECDSA(hashes.SHA256()))
print('signed', mj['id'], mj['version'], len(files), 'files, uuid', uuid)
