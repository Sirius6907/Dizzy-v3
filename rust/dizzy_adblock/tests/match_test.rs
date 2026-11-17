use dizzy_adblock::api::DizzyEngine;

const RULES: &str = "\
||vinnyvower.cfd^
||contain.remanpurflertawneys.cyou^
||googletagmanager.com^$third-party
@@||vidfast.vc^$document
";

fn engine() -> DizzyEngine {
    DizzyEngine::from_rules(RULES.lines().map(String::from).collect())
}

#[test]
fn blocks_known_ad_hosts() {
    let e = engine();
    assert!(e.match_request(
        "https://vinnyvower.cfd/cuid/?f=https%3A%2F%2Fvidfast.vc",
        "vidfast.vc",
        "xmlhttprequest",
    ));
    assert!(e.match_request(
        "https://contain.remanpurflertawneys.cyou/gd/137978?md=abc",
        "vidfast.vc",
        "xmlhttprequest",
    ));
}

#[test]
fn blocks_third_party_tag_manager() {
    let e = engine();
    assert!(e.match_request(
        "https://www.googletagmanager.com/gtag/js?id=G-XYZ",
        "vidfast.vc",
        "script",
    ));
}

#[test]
fn allows_media_and_site_traffic() {
    let e = engine();
    assert!(!e.match_request("https://vidfast.vc/movie/550", "vidfast.vc", "document"));
    // A CDN m3u8 from a random media host must never be blocked.
    assert!(!e.match_request(
        "https://some-cdn.example.net/hls/550/index.m3u8",
        "vidfast.vc",
        "xhr",
    ));
}

#[test]
fn unparseable_request_is_allowed() {
    let e = engine();
    assert!(!e.match_request("not a url", "vidfast.vc", "xhr"));
}
