import hashlib, hmac

secret_key = "9fd3a0195e5be1ec526cca03d4ace9db8ba830ebf839871e8db5c67e091ec461"
amz_date   = "20260315T100637Z"
date_stamp = "20260315"
region     = "garage"
service    = "s3"

canonical_request = "PUT\n/md-spielplatznadel/Untitled.jpg\n\ncontent-type:image/jpeg\nhost:localhost:8001\nx-amz-content-sha256:ebb3507d5e4cfae9a33d292f019e86d13e1dfdb17ba1eaeb4a720f29e681fce0\nx-amz-date:20260315T100637Z\n\ncontent-type;host;x-amz-content-sha256;x-amz-date\nebb3507d5e4cfae9a33d292f019e86d13e1dfdb17ba1eaeb4a720f29e681fce0"

cr_hash = hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()
print("canonical request hash:", cr_hash)
print("elm canonical request hash:", "36f83833455ab48e7bb55ab3cfe2b45fab9d45df2a17a0fe5be7a69e210ef1b9")
print("hashes match:", cr_hash == "36f83833455ab48e7bb55ab3cfe2b45fab9d45df2a17a0fe5be7a69e210ef1b9")

credential_scope = f"{date_stamp}/{region}/{service}/aws4_request"
string_to_sign = f"AWS4-HMAC-SHA256\n{amz_date}\n{credential_scope}\n{cr_hash}"

def sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()

k = sign(("AWS4" + secret_key).encode('utf-8'), date_stamp)
k = sign(k, region)
k = sign(k, service)
k = sign(k, "aws4_request")

sig = hmac.new(k, string_to_sign.encode('utf-8'), hashlib.sha256).hexdigest()
print("python signature:", sig)
print("elm signature:   ", "9a0de107a6e81d384239fe7f561ea4ff1f50ab86fd7668fc64226bf6f58b7f2a")
print("signatures match:", sig == "9a0de107a6e81d384239fe7f561ea4ff1f50ab86fd7668fc64226bf6f58b7f2a")
