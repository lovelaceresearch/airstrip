import argparse
import json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if args.json:
        print(json.dumps({"message": "Hello from Airstrip", "ok": True}, indent=2))
    else:
        print("Hello from Airstrip.")
        print("This is a tiny CLI app for action/log testing.")


if __name__ == "__main__":
    main()
