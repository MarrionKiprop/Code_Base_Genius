# gents/supervisor.jac
import from repo_mapper { RepoMapper }
import from code_analyzer { CodeAnalyzer, File, Class, Function }
import from doc_genie { DocGenie }
import os;
import re;
import shutil;
def is_valid_github_url(url: str) -> bool {
    pattern = r"^(https?://)?(www\.)?github\.com/[^/]+/[^/]+(\.git)?/?$";
    return bool(re.match(pattern, url));
}

def repo_name_from_url(u: str) -> str {
    parts = u.strip("/").split("/");
    if len(parts) > 0 {
        return parts[-1].replace(".git", "");
    } else {
        return "repo";
    }
}

# Main supervisor walker for Codebase Genius

walker codegenius_supervisor {
    obj __specs__ {
    static has auth: bool = False;
}
    has repo_url: str = "";
    has prioritize_entrypoints: bool = True;
    has files: list[str] = [];
    has priority: list[str] = [];
    has others: list[str] = [];

    can execute with `root entry {
        print("Codebase Genius Supervisor starting...");

        if not self.repo_url {
            report {"error": "repo_url required"};
            disengage;
        }

        if not is_valid_github_url(self.repo_url) {
            report {"error": "Invalid GitHub URL"};
            disengage;
        }

        mapper = RepoMapper(repo_url=self.repo_url);
        root ++> mapper;
        mapper.map(self);

        if not mapper.file_index or len(mapper.file_index) == 0 {
            print("No files found in repository.");
            report {"status": "failed", "reason": "empty or inaccessible repository"};
            disengage;
        }

        print("Files cloned and indexed: " + str(len(mapper.file_index)));

        self.files = mapper.file_index;
        self.priority = [];
        self.others = [];

        if self.prioritize_entrypoints {
            for p in self.files {
                let low = p.lower();
                if (
                    ("main.py" in low)
                    or ("app.py" in low)
                    or ("run.py" in low)
                    or ("__init__.py" in low)
                    or ("server.py" in low)
                ) {
                    self.priority = self.priority + [p];
                } else {
                    self.others = self.others + [p];
                }
            }
        } else {
            self.others = self.files;
        }

        print("Entrypoints: " + str(len(self.priority)));
        print("Other files: " + str(len(self.others)));

            analyzer = CodeAnalyzer(repo_dir=mapper.repo_path, files=self.priority + self.others);
            root ++> analyzer;
            analyzer.analyze(self);

            let parsed_files = analyzer.parsed_count;
            print("Code analysis complete. Files parsed (derived): " + str(parsed_files));

    doc = DocGenie(
        temp_dir=mapper.temp_dir,
        repo_name=repo_name_from_url(self.repo_url),
        readme_summary=mapper.readme_summary,
        file_index=mapper.file_index,
        ccg_nodes=analyzer.graph_view()  
    );
    root ++> doc;
    doc.generate(self);

    # Entry walker invocation
    root ++> doc;
    md_path = doc.output_md;

    if not md_path or not os.path.exists(md_path) {
        print("No markdown path returned directly from DocGenie, checking output_md...");
        md_path = doc.output_md;
    }

    print("Documentation generated successfully!");

md_text = "";
# Always publish to a stable, project-root folder
let base_dir = os.getcwd();
let public_dir = os.path.join(base_dir, "generated_docs");

if not os.path.exists(public_dir) {
    os.makedirs(public_dir);
}

if md_path and os.path.exists(md_path) {
    md_text = open(md_path, "r", encoding="utf-8").read();
    print("Markdown loaded, length: " + str(len(md_text)) + " chars");

    let repo_slug = repo_name_from_url(self.repo_url).replace("/", "_");
    let final_path = os.path.join(public_dir, repo_slug + ".md");

    open(final_path, "w", encoding="utf-8").write(md_text);
    print("Documentation saved at: " + final_path);

    # Only expose the clean, stable path going forward
    md_path = final_path;
} else {
    print("Markdown file missing or not accessible at: " + str(md_path));
}

# --- add clear metrics and only report stable paths ---

let total_files = len(mapper.file_index);
let sampled_files = len(self.priority + self.others);  # analyzed set
let parsed_files_count = parsed_files;

result = {
    "status": "ok",
    "repo": self.repo_url,
    "total_files": total_files,
    "sampled_files": sampled_files,
    "files_parsed": parsed_files_count,
    "output_md": md_path,        # <- stable path only
    "markdown_text": md_text
};

print(
    "Report finalized. "
    + "Total=" + str(total_files)
    + ", Sampled=" + str(sampled_files)
    + ", Parsed=" + str(parsed_files_count)
    + ", Out=" + md_path
);
report result;
return result;
    }
}