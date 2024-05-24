use anyhow::Result;
use schemars::{schema_for, JsonSchema};
use spin_sdk::{
    http::{IntoResponse, Params, Request, Response, Router},
    http_component,
};

#[derive(serde::Serialize, JsonSchema)]
struct Playground {
    id: String,
    size: Size,
}

#[derive(serde::Serialize, JsonSchema)]
enum Size {
    Small,
    Medium,
    Large(String),
}

/// A Spin HTTP component that internally routes requests.
#[http_component]
fn handle_route(req: Request) -> Response {
    let mut router = Router::new();
    router.get("/api/playground", api::playground_all);
    router.get("/api/schema", api::schema);
    // router.any_async("/*", api::echo_wildcard);
    router.handle(req)
}

mod api {
    use super::*;

    // /playground
    pub fn playground_all(_req: Request, _params: Params) -> Result<impl IntoResponse> {
        let p1 = Playground {
            id: "some_id".to_string(),
            size: Size::Medium,
        };
        Ok(Response::new(200, serde_json::to_string(&p1)?))
    }

    pub fn schema(_req: Request, _params: Params) -> Result<impl IntoResponse> {
        let schema = schema_for!(Playground);
        Ok(Response::new(200, serde_json::to_string_pretty(&schema)?))
    }

    // /goodbye/:planet
    pub fn goodbye_planet(_req: Request, params: Params) -> Result<impl IntoResponse> {
        let planet = params.get("planet").expect("PLANET");
        Ok(Response::new(200, planet.to_string()))
    }

    // /*
    pub async fn echo_wildcard(_req: Request, params: Params) -> Result<impl IntoResponse> {
        let capture = params.wildcard().unwrap_or_default();
        Ok(Response::new(200, capture.to_string()))
    }
}
