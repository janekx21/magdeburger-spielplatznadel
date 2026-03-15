module GarageUpload exposing (Config, bytesToHex, formatAmzDate, hexToBytes, hmac, hmacHex, uploadFile, utf8)

{-| Upload files to a Garage S3 bucket using AWS Signature V4.

    Required packages:
        elm install folkertdev/elm-sha2
        elm install elm/bytes
        elm install elm/http
        elm install elm/time

    Usage:

        -- In development, endpoint is the Lamdera proxy and host matches it.
        -- In production, both point directly at Garage.
        GarageUpload.uploadFile
            { endpoint  = "http://localhost:8001"   -- URL the browser sends to (no trailing slash)
            , host      = "localhost:8001"           -- Host header value (must match endpoint)
            , bucket    = "my-bucket"
            , region    = "garage"
            , accessKey = "GKxxx"
            , secretKey = "xxx"
            }
            "photo.jpg"
            "image/jpeg"
            myBytes
            UploadFinished

-}

import Bitwise
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode as Encode
import Http
import SHA256
import Task
import Time



-- CONFIG


type alias Config =
    { endpoint : String -- URL the browser sends to        e.g. "http://localhost:8001"  (no trailing slash)
    , host : String -- Host header (must match URL)    e.g. "localhost:8001"
    , bucket : String -- e.g. "my-bucket"
    , region : String -- e.g. "garage"
    , accessKey : String
    , secretKey : String
    }



-- PUBLIC API


{-| Upload raw Bytes to Garage using AWS Signature V4.

    The object will be available at:
        <endpoint>/<bucket>/<key>

    Or via the Garage web endpoint:
        http://<bucket>.web.garage.localhost:3902/<key>

-}
uploadFile :
    Config
    -> String -- object key  e.g. "photo.jpg"
    -> String -- content-type e.g. "image/jpeg"
    -> Bytes -- raw file bytes
    -> (Result Http.Error () -> msg)
    -> Cmd msg
uploadFile config key contentType body toMsg =
    Time.now
        |> Task.andThen (\posix -> buildHttpTask config key contentType body posix)
        |> Task.attempt toMsg



-- INTERNAL


buildHttpTask :
    Config
    -> String
    -> String
    -> Bytes
    -> Time.Posix
    -> Task.Task Http.Error ()
buildHttpTask config key contentType body posix =
    let
        amzDate =
            formatAmzDate posix

        dateStamp =
            String.left 8 amzDate

        host =
            config.host

        -- Hash the request body (SHA-256 of raw bytes -> hex string)
        bodyHex =
            SHA256.fromBytes body |> SHA256.toHex

        -- Canonical request
        canonicalHeaders =
            "content-type:"
                ++ contentType
                ++ "\n"
                ++ "host:"
                ++ host
                ++ "\n"
                ++ "x-amz-content-sha256:"
                ++ bodyHex
                ++ "\n"
                ++ "x-amz-date:"
                ++ amzDate
                ++ "\n"

        signedHeaders =
            "content-type;host;x-amz-content-sha256;x-amz-date"

        canonicalRequest =
            "PUT\n"
                ++ "/"
                ++ config.bucket
                ++ "/"
                ++ key
                ++ "\n"
                ++ "\n"
                ++ canonicalHeaders
                ++ "\n"
                ++ signedHeaders
                ++ "\n"
                ++ bodyHex

        -- String to sign
        credentialScope =
            dateStamp ++ "/" ++ config.region ++ "/s3/aws4_request"

        stringToSign =
            "AWS4-HMAC-SHA256\n"
                ++ amzDate
                ++ "\n"
                ++ credentialScope
                ++ "\n"
                ++ (SHA256.fromBytes (utf8 canonicalRequest) |> SHA256.toHex)

        -- Signing key: 4 rounds of HMAC-SHA256
        -- Round 1 key is the UTF-8 bytes of "AWS4" ++ secretKey
        -- Each subsequent round feeds the raw Bytes output of the previous round as key
        -- hmac : message -> key -> Bytes  (pipeable: output Bytes becomes key of next round)
        signingKey =
            hmac (utf8 dateStamp) (utf8 ("AWS4" ++ config.secretKey))
                |> hmac (utf8 config.region)
                |> hmac (utf8 "s3")
                |> hmac (utf8 "aws4_request")

        -- Final signature: HMAC of stringToSign, output as hex
        signature =
            hmacHex (utf8 stringToSign) signingKey

        -- Authorization header
        authorization =
            "AWS4-HMAC-SHA256 Credential="
                ++ config.accessKey
                ++ "/"
                ++ credentialScope
                ++ ", SignedHeaders="
                ++ signedHeaders
                ++ ", Signature="
                ++ signature

        _ =
            Debug.log "amzDate" amzDate

        _ =
            Debug.log "dateStamp" dateStamp

        _ =
            Debug.log "host" host

        _ =
            Debug.log "bodyHex" bodyHex

        _ =
            Debug.log "canonicalHeaders" canonicalHeaders

        _ =
            Debug.log "canonicalRequest" canonicalRequest

        _ =
            Debug.log "stringToSign" stringToSign

        _ =
            Debug.log "signature" signature
    in
    Http.task
        { method = "PUT"
        , headers =
            [ Http.header "Authorization" authorization
            , Http.header "x-amz-date" amzDate
            , Http.header "x-amz-content-sha256" bodyHex
            ]
        , url = config.endpoint ++ "/" ++ config.bucket ++ "/" ++ key
        , body = Http.bytesBody contentType body
        , resolver = Http.bytesResolver (\_ -> Ok ())
        , timeout = Nothing
        }



-- HMAC-SHA256
--
-- HMAC(key, msg) = SHA256( (key XOR opad) ++ SHA256( (key XOR ipad) ++ msg ) )
--
-- The signing key chain passes raw digest Bytes from one round to the next,
-- which is required for correct AWS Signature V4 behaviour.


{-| Compute HMAC-SHA256. Takes a key as Bytes, a message as Bytes,
and returns Bytes so rounds can be piped into each other.
-}
hmac : Bytes -> Bytes -> Bytes
hmac message key =
    let
        blockSize =
            64

        -- If key is longer than blockSize, hash it down to 32 bytes
        normalizedKey =
            if Bytes.width key > blockSize then
                SHA256.fromBytes key |> digestToBytes

            else
                key

        -- Pad key to blockSize with zero bytes on the right
        paddedKey =
            padRight blockSize normalizedKey

        -- XOR padded key with ipad (0x36) and opad (0x5C)
        innerKey =
            xorWithByte 0x36 paddedKey

        outerKey =
            xorWithByte 0x5C paddedKey

        -- Inner: SHA256( innerKey ++ message )
        innerHash =
            SHA256.fromBytes (appendBytes innerKey message) |> digestToBytes

        -- Outer: SHA256( outerKey ++ innerHash )
    in
    SHA256.fromBytes (appendBytes outerKey innerHash) |> digestToBytes


{-| Compute HMAC-SHA256 and return the result as a hex String.
Used only for the final signature step.
-}
hmacHex : Bytes -> Bytes -> String
hmacHex message key =
    hmac message key |> bytesToHex


digestToBytes : SHA256.Digest -> Bytes
digestToBytes digest =
    digest |> SHA256.toHex |> hexToBytes


bytesToHex : Bytes -> String
bytesToHex bytes =
    bytesToList bytes
        |> List.map (\b -> String.padLeft 2 '0' (hexFromInt b))
        |> String.concat


hexFromInt : Int -> String
hexFromInt n =
    let
        digits =
            "0123456789abcdef"

        high =
            n // 16

        low =
            modBy 16 n

        charAt i =
            String.slice i (i + 1) digits
    in
    charAt high ++ charAt low


xorWithByte : Int -> Bytes -> Bytes
xorWithByte b bytes =
    bytesToList bytes
        |> List.map (Bitwise.xor b)
        |> listToBytes


padRight : Int -> Bytes -> Bytes
padRight targetLen bytes =
    let
        padding =
            List.repeat (max 0 (targetLen - Bytes.width bytes)) 0
    in
    appendBytes bytes (listToBytes padding)


appendBytes : Bytes -> Bytes -> Bytes
appendBytes a b =
    Encode.encode
        (Encode.sequence [ Encode.bytes a, Encode.bytes b ])



-- BYTE / HEX HELPERS


utf8 : String -> Bytes
utf8 s =
    Encode.encode (Encode.string s)


listToBytes : List Int -> Bytes
listToBytes list =
    list
        |> List.map Encode.unsignedInt8
        |> Encode.sequence
        |> Encode.encode


bytesToList : Bytes -> List Int
bytesToList bytes =
    let
        decoder =
            Bytes.Decode.loop ( Bytes.width bytes, [] )
                (\( remaining, acc ) ->
                    if remaining == 0 then
                        Bytes.Decode.succeed (Bytes.Decode.Done (List.reverse acc))

                    else
                        Bytes.Decode.map
                            (\byte -> Bytes.Decode.Loop ( remaining - 1, byte :: acc ))
                            Bytes.Decode.unsignedInt8
                )
    in
    Bytes.Decode.decode decoder bytes
        |> Maybe.withDefault []


hexToBytes : String -> Bytes
hexToBytes hex =
    hex
        |> String.toList
        |> chunkPairs
        |> List.filterMap hexPairToInt
        |> listToBytes


chunkPairs : List Char -> List String
chunkPairs chars =
    case chars of
        a :: b :: rest ->
            (String.fromChar a ++ String.fromChar b) :: chunkPairs rest

        _ ->
            []


hexPairToInt : String -> Maybe Int
hexPairToInt s =
    case String.toList (String.toLower s) of
        [ a, b ] ->
            Maybe.map2 (\hi lo -> hi * 16 + lo)
                (hexDigit a)
                (hexDigit b)

        _ ->
            Nothing


hexDigit : Char -> Maybe Int
hexDigit c =
    case c of
        '0' ->
            Just 0

        '1' ->
            Just 1

        '2' ->
            Just 2

        '3' ->
            Just 3

        '4' ->
            Just 4

        '5' ->
            Just 5

        '6' ->
            Just 6

        '7' ->
            Just 7

        '8' ->
            Just 8

        '9' ->
            Just 9

        'a' ->
            Just 10

        'b' ->
            Just 11

        'c' ->
            Just 12

        'd' ->
            Just 13

        'e' ->
            Just 14

        'f' ->
            Just 15

        _ ->
            Nothing



-- DATE FORMATTING
-- AWS requires: "20260314T152346Z"


formatAmzDate : Time.Posix -> String
formatAmzDate posix =
    let
        z =
            Time.utc

        year =
            Time.toYear z posix |> String.fromInt

        month =
            Time.toMonth z posix |> monthToInt |> pad2

        day =
            Time.toDay z posix |> String.fromInt |> pad2

        hour =
            Time.toHour z posix |> String.fromInt |> pad2

        minute =
            Time.toMinute z posix |> String.fromInt |> pad2

        second =
            Time.toSecond z posix |> String.fromInt |> pad2
    in
    year ++ month ++ day ++ "T" ++ hour ++ minute ++ second ++ "Z"


pad2 : String -> String
pad2 s =
    if String.length s < 2 then
        "0" ++ s

    else
        s


monthToInt : Time.Month -> String
monthToInt month =
    case month of
        Time.Jan ->
            "1"

        Time.Feb ->
            "2"

        Time.Mar ->
            "3"

        Time.Apr ->
            "4"

        Time.May ->
            "5"

        Time.Jun ->
            "6"

        Time.Jul ->
            "7"

        Time.Aug ->
            "8"

        Time.Sep ->
            "9"

        Time.Oct ->
            "10"

        Time.Nov ->
            "11"

        Time.Dec ->
            "12"


stripScheme : String -> String
stripScheme url =
    url
        |> String.replace "https://" ""
        |> String.replace "http://" ""
