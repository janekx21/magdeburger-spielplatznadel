module GarageUploadTest exposing (suite)

{-| Tests for GarageUpload internals.

    Run with:
        elm-test

    Required packages:
        elm install elm-explorations/test
        elm install folkertdev/elm-sha2

    These tests use known HMAC-SHA256 test vectors from RFC 4231
    and the AWS Signature V4 test suite to verify correctness.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as Encode
import Expect
import GarageUpload exposing (..)
import SHA256
import Test exposing (Test, describe, test)
import Time



-- We need access to the internal functions for unit testing.
-- Expose them from GarageUpload, or copy them here for testing.
-- The cleanest approach is to expose internals via a separate
-- GarageUpload.Internal module, but for now we test via
-- the public hmacHex helper if exposed, or duplicate here.
--
-- For these tests to compile, add the following to GarageUpload's
-- exposing list:
--   module GarageUpload exposing (Config, uploadFile, hmac, hmacHex, bytesToHex, hexToBytes, utf8)


suite : Test
suite =
    describe "GarageUpload"
        [ hmacTests
        , hexTests
        , dateTests
        , signingKeyTests
        , curlRequestTest
        ]



-- HMAC-SHA256 TESTS
-- Test vectors from RFC 4231 (https://www.rfc-editor.org/rfc/rfc4231)
-- and ktonon/elm-crypto's own documented examples.


hmacTests : Test
hmacTests =
    describe "hmac / hmacHex"
        [ test "RFC 4231 Test Case 1 - basic key and data" <|
            \_ ->
                -- Key:  0x0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b (20 bytes)
                -- Data: "Hi There"
                -- Expected HMAC-SHA256: b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7
                let
                    key =
                        List.repeat 20 0x0B |> listToBytes

                    message =
                        utf8 "Hi There"
                in
                hmacHex message key
                    |> Expect.equal "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        , test "RFC 4231 Test Case 2 - key shorter than block size" <|
            \_ ->
                -- Key:  "Jefe"
                -- Data: "what do ya want for nothing?"
                -- Expected: 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964a66852
                hmacHex (utf8 "what do ya want for nothing?") (utf8 "Jefe")
                    |> Expect.equal "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        , test "ktonon/elm-crypto reference vector" <|
            \_ ->
                -- From ktonon/elm-crypto README:
                -- HMAC-SHA256 key="key" msg="The quick brown fox jumps over the lazy dog"
                -- Expected: f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8
                hmacHex
                    (utf8 "The quick brown fox jumps over the lazy dog")
                    (utf8 "key")
                    |> Expect.equal "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        , test "RFC 4231 Test Case 3 - key longer than block size (gets hashed)" <|
            \_ ->
                -- Key:  0xaa repeated 131 times (longer than 64-byte block size)
                -- Data: "Test Using Larger Than Block-Size Key - Hash Key First"
                -- Expected: 60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54
                let
                    key =
                        List.repeat 131 0xAA |> listToBytes

                    message =
                        utf8 "Test Using Larger Than Block-Size Key - Hash Key First"
                in
                hmacHex message key
                    |> Expect.equal "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
        ]



-- HEX / BYTE CONVERSION TESTS


hexTests : Test
hexTests =
    describe "hex / byte helpers"
        [ test "bytesToHex produces lowercase hex" <|
            \_ ->
                [ 0x00, 0xFF, 0x0F, 0xF0, 0xAB, 0xCD ]
                    |> listToBytes
                    |> bytesToHex
                    |> Expect.equal "00ff0ff0abcd"
        , test "hexToBytes round-trips with bytesToHex" <|
            \_ ->
                let
                    original =
                        [ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF ]

                    hex =
                        original |> listToBytes |> bytesToHex
                in
                hexToBytes hex
                    |> bytesToHex
                    |> Expect.equal hex
        , test "utf8 encodes ASCII string correctly" <|
            \_ ->
                utf8 "ABC"
                    |> bytesToHex
                    |> Expect.equal "414243"
        ]



-- DATE FORMATTING TESTS


dateTests : Test
dateTests =
    describe "formatAmzDate"
        [ test "formats a known timestamp correctly" <|
            \_ ->
                -- 2013-05-24T00:00:00Z = 1369353600000 ms
                -- This is the date used in AWS Signature V4 test suite
                Time.millisToPosix 1369353600000
                    |> formatAmzDate
                    |> Expect.equal "20130524T000000Z"
        , test "pads single-digit month and day" <|
            \_ ->
                -- 2025-01-05T08:50:23Z = 1736067023000 ms
                Time.millisToPosix 1736067023000
                    |> formatAmzDate
                    |> Expect.equal "20250105T085023Z"
        ]



-- AWS SIGNING KEY CHAIN TEST
-- The AWS Signature V4 test suite publishes known signing key values.
-- https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
--
-- Secret:  "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
-- Region:  "us-east-1"
-- Service: "iam"
-- Date:    "20110909"
--
-- Expected signing key (hex):
--   98f1d889fec4f4421adc522bab0ce1f82e6929c262ed15e5a94c90efd1e3b0e7


signingKeyTests : Test
signingKeyTests =
    describe "AWS signing key derivation"
        [ test "derives correct signing key for AWS test suite vector" <|
            \_ ->
                let
                    secretKey =
                        "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"

                    dateStamp =
                        "20110909"

                    region =
                        "us-east-1"

                    service =
                        "iam"

                    signingKey =
                        hmac (utf8 dateStamp) (utf8 ("AWS4" ++ secretKey))
                            |> hmac (utf8 region)
                            |> hmac (utf8 service)
                            |> hmac (utf8 "aws4_request")
                            |> bytesToHex
                in
                signingKey
                    |> Expect.equal "98f1d889fec4f4421adc522bab0ce1f82e6929c262ed15e5a94c90efd1e3b0e7"
        ]



-- HELPERS (duplicated from GarageUpload internals for test access)
-- Remove these if you expose them directly from GarageUpload.


listToBytes : List Int -> Bytes
listToBytes list =
    list
        |> List.map Encode.unsignedInt8
        |> Encode.sequence
        |> Encode.encode



-- REAL CURL REQUEST TEST
-- Taken from a real curl --aws-sigv4 verbose upload to Garage.
-- All intermediate values are known from the curl output.
--
-- curl -X PUT
--   --user "GK5c09e755b7cea71a1b72c46a:9fd3a0195e5be1ec526cca03d4ace9db8ba830ebf839871e8db5c67e091ec461"
--   --aws-sigv4 "aws:amz:garage:s3"
--   --data-binary @msg.txt   (content: "Hello World!\n", 13 bytes)
--   "http://localhost:3900/md-spielplatznadel/msg3.txt"
--
-- Note: curl signs host;x-amz-content-sha256;x-amz-date (no content-type).


curlRequestTest : Test
curlRequestTest =
    describe "real curl request vector"
        [ test "body SHA256 matches curl output" <|
            \_ ->
                -- msg.txt = "Hello World!\n" (13 bytes, 0x48 65 6c 6c 6f 20 57 6f 72 6c 64 21 0a)
                -- curl reported: 6ecef25148714c8dac4484dd375ecf29f47bc36913d0d162c757e3bb47be4c2a
                utf8 "Hello World 222!\n"
                    |> SHA256.fromBytes
                    |> SHA256.toHex
                    |> Expect.equal "6ecef25148714c8dac4484dd375ecf29f47bc36913d0d162c757e3bb47be4c2a"
        , test "canonical request SHA256 matches curl string-to-sign" <|
            \_ ->
                -- curl canonical request (no content-type in signed headers):
                --   PUT
                --   /md-spielplatznadel/msg3.txt
                --
                --   host:localhost:3900
                --   x-amz-content-sha256:6ecef251...
                --   x-amz-date:20260314T162236Z
                --
                --   host;x-amz-content-sha256;x-amz-date
                --   6ecef251...
                --
                -- SHA256 of that = 8f64e7bcf240c4bd466951f410a2ed757abd5fcffdcd1720948f830da8c70f8e
                let
                    bodyHex =
                        "6ecef25148714c8dac4484dd375ecf29f47bc36913d0d162c757e3bb47be4c2a"

                    canonicalRequest =
                        "PUT\n"
                            ++ "/md-spielplatznadel/msg3.txt\n"
                            ++ "\n"
                            ++ "host:localhost:3900\n"
                            ++ "x-amz-content-sha256:"
                            ++ bodyHex
                            ++ "\n"
                            ++ "x-amz-date:20260314T162236Z\n"
                            ++ "\n"
                            ++ "host;x-amz-content-sha256;x-amz-date\n"
                            ++ bodyHex
                in
                SHA256.fromString canonicalRequest
                    |> SHA256.toHex
                    |> Expect.equal "8f64e7bcf240c4bd466951f410a2ed757abd5fcffdcd1720948f830da8c70f8e"
        , test "signing key derivation matches for garage credentials" <|
            \_ ->
                -- Secret:  "9fd3a0195e5be1ec526cca03d4ace9db8ba830ebf839871e8db5c67e091ec461"
                -- Date:    "20260314"
                -- Region:  "garage"
                -- Service: "s3"
                hmac (utf8 "20260314") (utf8 "AWS49fd3a0195e5be1ec526cca03d4ace9db8ba830ebf839871e8db5c67e091ec461")
                    |> hmac (utf8 "garage")
                    |> hmac (utf8 "s3")
                    |> hmac (utf8 "aws4_request")
                    |> (\signingKey ->
                            -- String to sign from curl:
                            --   AWS4-HMAC-SHA256
                            --   20260314T162236Z
                            --   20260314/garage/s3/aws4_request
                            --   8f64e7bcf240c4bd466951f410a2ed757abd5fcffdcd1720948f830da8c70f8e
                            let
                                stringToSign =
                                    "AWS4-HMAC-SHA256\n"
                                        ++ "20260314T162236Z\n"
                                        ++ "20260314/garage/s3/aws4_request\n"
                                        ++ "8f64e7bcf240c4bd466951f410a2ed757abd5fcffdcd1720948f830da8c70f8e"
                            in
                            hmacHex (utf8 stringToSign) signingKey
                       )
                    |> Expect.equal "416433d8b6ff9029eeb924f6f3b5422dbc327a9b32bd0edb7dc849ee8fa50760"
        ]
