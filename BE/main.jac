# main.jac
import from dotenv { load_dotenv }
import from byllm.llm { Model }
import from supervisor { codegenius_supervisor }
import sys;

glob llm = Model(model_name="openai/gpt-4o-mini", verbose=False);

with entry {
    load_dotenv();
    print("Codebase Genius loaded into Jac Cloud!");

    url = "";
    if "--url" in sys.argv {
        idx = sys.argv.index("--url") + 1;
        if idx < len(sys.argv) { url = sys.argv[idx]; }
    }

    # DO NOT disengage or return
    # Just spawn — or do nothing if no URL
    if url {
        root spawn codegenius_supervisor({"repo_url": url});
    } else {
        print("No --url provided. Use: jac serve main.jac && curl ...");
        print("Example:");
        #print("  curl -X POST http://localhost:4111/run_walker -d '{\"walker\":\"entry\",\"args\":{\"url\":\"https://github.com/jac-lang/examples\"}}'");
    }
}