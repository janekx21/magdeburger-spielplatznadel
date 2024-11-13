use base64::prelude::*;
use image::{GenericImageView, ImageReader};
use once_cell::sync::Lazy;
use salvo::catcher::Catcher;
use salvo::oapi::extract::*;
use salvo::{prelude::*, Error as SalvoError, Result};
use serde::{Deserialize, Serialize};
use std::fmt::Debug;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use tokio::fs;
use uuid::Uuid;

// HD format
const MAX_IMAGE_BIG: u32 = 1280;
const MAX_IMAGE_SMALL: u32 = 720;

static LAZY_API_KEY: Lazy<String> =
    Lazy::new(|| std::env::var("BACKEND_API_KEY").unwrap_or("".to_string()));

#[derive(Serialize, Deserialize, ToSchema, Debug)]
struct PostImageParams {
    /// Base 64 representation
    data: String,
}

#[derive(Serialize, Deserialize, ToSchema, Debug)]
struct PostImageResult {
    id: Uuid,
    width: u32,
    height: u32,
    delete_token: Uuid,
}

#[endpoint]
async fn get_image(id: PathParam<Uuid>, req: &mut Request, res: &mut Response) {
    res.send_file(image_path(id.0), req.headers()).await;
}

#[endpoint]
async fn post_image(
    api_key: PathParam<String>,
    params: JsonBody<PostImageParams>,
) -> Result<Json<PostImageResult>> {
    authorize(api_key.0)?;

    let data = BASE64_STANDARD
        .decode(params.data.clone())
        .map_err(|e| SalvoError::HttpStatus(StatusError::bad_request().cause(e)))?;

    let image = ImageReader::new(Cursor::new(data))
        .with_guessed_format()?
        .decode()
        .map_err(|e| SalvoError::HttpStatus(StatusError::bad_request().cause(e)))?;

    let (width, height) = image.dimensions();

    let (width, height) = if width > height {
        // Landscape
        (width.min(MAX_IMAGE_BIG), height.min(MAX_IMAGE_SMALL))
    } else {
        // Portai
        (width.min(MAX_IMAGE_SMALL), height.min(MAX_IMAGE_BIG))
    };

    let image = image.resize_to_fill(width, height, image::imageops::FilterType::Lanczos3);
    let image = image.into_rgb8(); // remove alpha channel

    let id = Uuid::new_v4();
    let delete_token = Uuid::new_v4();

    fs::symlink(
        Path::new("../..").join(image_path(id)),
        delete_token_path(delete_token),
    )
    .await?;

    let image_path = image_path(id);
    image
        .save(&image_path)
        .map_err(|e| SalvoError::HttpStatus(StatusError::internal_server_error().cause(e)))?;

    let (width, height) = image.dimensions();

    log::info!("post image at {image_path:?}");

    Ok(Json(PostImageResult {
        id,
        width,
        height,
        delete_token,
    }))
}

#[endpoint]
async fn delete_image(delete_token: PathParam<Uuid>, api_key: PathParam<String>) -> Result<()> {
    authorize(api_key.0)?;
    let link_path = delete_token_path(delete_token.0);
    let path = fs::read_link(&link_path)
        .await
        .map_err(|e| SalvoError::HttpStatus(StatusError::not_found().cause(e)))?;

    let image_path = link_path
        .parent() // remove the symlink
        .ok_or(SalvoError::HttpStatus(StatusError::internal_server_error()))?
        .join(path);

    fs::remove_file(&image_path)
        .await
        .map_err(|_| SalvoError::HttpStatus(StatusError::internal_server_error()))?;

    fs::remove_file(link_path)
        .await
        .map_err(|_| SalvoError::HttpStatus(StatusError::internal_server_error()))?;

    log::info!("deleted image at {image_path:?} with delete token");

    Ok(())
}

fn authorize(api_key: String) -> Result<()> {
    if api_key != *LAZY_API_KEY {
        return Err(SalvoError::HttpStatus(
            StatusError::unauthorized().cause("wrong api key"),
        ));
    }
    Ok(())
}

fn image_path(id: Uuid) -> PathBuf {
    Path::new("data/image").join(format!("{id}.jpeg"))
}

fn delete_token_path(delete_token: Uuid) -> PathBuf {
    Path::new("data/delete_token").join(format!("{delete_token}"))
}

#[handler]
fn response_logging(req: &mut Request, res: &mut Response) {
    if res.status_code == Some(StatusCode::INTERNAL_SERVER_ERROR) {
        log::error!("internal server error: {:?}", res);
    }
    if res.status_code == Some(StatusCode::UNAUTHORIZED) {
        log::info!("unautherized request from {}", req.remote_addr_mut());
    }
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    simple_logger::SimpleLogger::new()
        .env()
        .with_colors(true)
        .init()
        .unwrap();

    fs::create_dir_all("data/image").await?;
    fs::create_dir_all("data/delete_token").await?;

    let router = Router::new().push(
        Router::with_path("image")
            .push(
                Router::with_path("<api_key>")
                    .post(post_image)
                    .push(Router::with_path("<delete_token>").delete(delete_image)),
            )
            .push(Router::with_path("<id>").get(get_image)),
    );

    let doc = OpenApi::new("Image upload API", "0.0.1").merge_router(&router);

    let router = router
        .push(doc.into_router("/api-doc/openapi.json"))
        .push(SwaggerUi::new("/api-doc/openapi.json").into_router("swagger-ui"));

    let acceptor = TcpListener::new("0.0.0.0:5800").bind().await;

    // let listener = TcpListener::new("0.0.0.0:443")
    //     .acme()
    //     .add_domain("localhost") // Replace this domain name with your own.
    //     .http01_challenge(&mut router)
    //     .quinn("0.0.0.0:443");
    // let acceptor = listener.join(TcpListener::new("0.0.0.0:80")).bind().await;
    let service = Service::new(router).catcher(Catcher::default().hoop(response_logging));
    Server::new(acceptor).serve(service).await;
    Ok(())
}
