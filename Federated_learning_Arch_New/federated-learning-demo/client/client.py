#!/usr/bin/env python3
"""
Federated Learning Client
Trains a logistic classifier locally on non-IID private data.
Shares only weight updates — raw data never leaves this process.
"""
import logging, os, time
import numpy as np
import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

SERVER       = os.environ.get("SERVER_URL", "http://server:8000")
CLIENT_ID    = os.environ.get("CLIENT_ID", "1")
POS          = [float(os.environ.get("POS_X","2.0")), float(os.environ.get("POS_Y","2.0"))]
NEG          = [float(os.environ.get("NEG_X","-2.0")), float(os.environ.get("NEG_Y","-2.0"))]
N_SAMPLES    = int(os.environ.get("N_SAMPLES","100"))
LOCAL_EPOCHS = int(os.environ.get("LOCAL_EPOCHS","15"))
LR           = 0.05
MAX_ROUNDS   = 15

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -500.0, 500.0)))

class Client:
    def __init__(self):
        np.random.seed(int(CLIENT_ID) * 1337)
        half = N_SAMPLES // 2
        X = np.vstack([np.random.randn(half, 2) + POS,
                       np.random.randn(half, 2) + NEG])
        y = np.array([1]*half + [0]*half)
        idx = np.random.permutation(N_SAMPLES)
        X, y = X[idx], y[idx]
        split = int(N_SAMPLES * 0.8)
        self.X_tr, self.y_tr = X[:split], y[:split]
        self.X_vl, self.y_vl = X[split:], y[split:]
        logger.info(f"Client {CLIENT_ID} | train={len(self.X_tr)} val={len(self.X_vl)}")
        logger.info(f"  non-IID: pos_center={POS}  neg_center={NEG}")

    def train(self, weights):
        w  = np.array(weights, dtype=float)
        Xa = np.column_stack([self.X_tr, np.ones(len(self.X_tr))])
        for _ in range(LOCAL_EPOCHS):
            yh   = sigmoid(Xa @ w)
            grad = Xa.T @ (yh - self.y_tr) / len(self.y_tr)
            w   -= LR * grad
        return w

    def evaluate(self, weights):
        w  = np.array(weights, dtype=float)
        Xa = np.column_stack([self.X_vl, np.ones(len(self.X_vl))])
        return float(np.mean((sigmoid(Xa @ w) >= 0.5).astype(int) == self.y_vl))

    def wait_server(self):
        for _ in range(60):
            try:
                if requests.get(f"{SERVER}/health", timeout=3).status_code == 200:
                    logger.info("Server ready."); return
            except Exception:
                pass
            time.sleep(2)
        raise RuntimeError("Server unreachable after 120s")

    def wait_for_demo_reset(self):
        """After a run completes, block until POST /demo/reset restores waiting_for_clients."""
        while True:
            try:
                s = requests.get(f"{SERVER}/status", timeout=5).json()
                if s["status"] == "waiting_for_clients" and s["round"] == 0:
                    return
            except Exception:
                pass
            time.sleep(1.5)

    def run(self):
        self.wait_server()
        while True:
            # Register when server is accepting clients (retry if training/completed)
            while True:
                time.sleep(int(CLIENT_ID) * 1.2)
                r = requests.post(f"{SERVER}/register", json={
                    "client_id": CLIENT_ID, "n_samples": len(self.X_tr),
                    "distribution": f"pos={POS} neg={NEG}",
                })
                if r.status_code == 409:
                    logger.info("Registration not open yet; retrying…")
                    time.sleep(2)
                    continue
                r.raise_for_status()
                logger.info(f"Registered: {r.json()}")
                break

            # Wait for all peers to join
            for _ in range(30):
                s = requests.get(f"{SERVER}/status").json()
                if s["status"] in ("training", "completed"):
                    break
                logger.info(f"Waiting for peers... ({s['status']})")
                time.sleep(2)

            current_round = -1
            while True:
                r = requests.get(f"{SERVER}/model").json()
                rnd, status = r["round"], r["status"]

                if status == "completed" or rnd > MAX_ROUNDS:
                    logger.info("Session complete. Waiting for demo reset (dashboard or POST /demo/reset)…")
                    break

                if rnd == current_round:
                    time.sleep(1); continue

                current_round = rnd
                logger.info(f"Round {rnd}: local training ({LOCAL_EPOCHS} epochs)...")
                local_w   = self.train(r["weights"])
                local_acc = self.evaluate(local_w.tolist())
                logger.info(f"Round {rnd}: local_acc={local_acc:.4f}")

                for attempt in range(5):
                    try:
                        resp = requests.post(f"{SERVER}/update", json={
                            "client_id": CLIENT_ID, "round": rnd,
                            "weights": local_w.tolist(),
                            "n_samples": len(self.X_tr),
                            "local_accuracy": local_acc,
                        }, timeout=30)
                        resp.raise_for_status()
                        logger.info(f"Round {rnd}: submitted → {resp.json()}")
                        break
                    except Exception as e:
                        logger.warning(f"Submit failed (attempt {attempt+1}): {e}")
                        time.sleep(2)

                time.sleep(0.3)

            self.wait_for_demo_reset()

if __name__ == "__main__":
    Client().run()
