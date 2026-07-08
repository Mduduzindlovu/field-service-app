import { LightningElement, wire } from "lwc";
import { loadScript, loadStyle } from "lightning/platformResourceLoader";
import MAPBOX_RESOURCE from "@salesforce/resourceUrl/mapboxgl";
import getOpenCases from "@salesforce/apex/CaseMapController.getOpenCases";

export default class CaseMapConsole extends LightningElement {
  map;
  mapboxgl;
  scriptsLoaded = false;
  renderAttempted = false;
  cases = [];
  error;

  @wire(getOpenCases)
  wiredCases({ data, error }) {
    if (data) {
      this.cases = data;
      if (this.scriptsLoaded) {
        this.renderPins();
      }
    } else if (error) {
      this.error = error;
    }
  }

  renderedCallback() {
    if (this.renderAttempted) {
      return;
    }
    this.renderAttempted = true;

    Promise.all([
      loadScript(this, MAPBOX_RESOURCE + "/mapbox-gl-csp.js"),
      loadStyle(this, MAPBOX_RESOURCE + "/mapbox-gl.css")
    ])
      .then(() => {
        console.log("Script loaded. window.mapboxgl:", window.mapboxgl);
        this.mapboxgl = window.mapboxgl;
        this.scriptsLoaded = true;
        this.initializeMap();
      })
      .catch((error) => {
        console.error("Script load failed:", error);
        this.error = error;
      });
  }

  initializeMap() {
    this.mapboxgl.accessToken =
      "MAPBOX_TOKEN_PLACEHOLDER"; // TODO: move to Custom Setting before production use

    this.mapboxgl.workerUrl = MAPBOX_RESOURCE + "/mapbox-gl-csp-worker.js";

    this.map = new this.mapboxgl.Map({
      container: this.template.querySelector(".map-container"),
      style: "mapbox://styles/mapbox/light-v11",
      center: [18.4241, -33.9249],
      zoom: 11
    });

    if (this.cases.length > 0) {
      this.renderPins();
    }
  }

  renderPins() {
    this.cases.forEach((c) => {
      if (c.latitude && c.longitude) {
        new this.mapboxgl.Marker()
          .setLngLat([c.longitude, c.latitude])
          .setPopup(
            new this.mapboxgl.Popup().setHTML(
              `<strong>${c.subject}</strong><br/>${c.locationName}<br/>Status: ${c.status}`
            )
          )
          .addTo(this.map);
      }
    });
  }
}
