# gents/doc_genie.jac
import from byllm.llm { Model }
import from code_analyzer { CodeAnalyzer, File, Class, Function }
import from repo_utils { get_timestamp}
import os;

glob llm = Model(model_name="openai/gpt-4o-mini", verbose=False);

node DocGenie {
    has temp_dir: str;
    has repo_name: str;
    has readme_summary: str = "";
    has output_md: str = "";
    has ccg_nodes: str = "";
    has file_index: list[str] = [];



    def mermaid_from_ccg() -> str {
        classes = [root --> (`?Class)];
        fns = [root --> (`?Function)];
        lines = ["graph TD"];

        for c in classes {
            cid = ("class_" + c.name).replace(" ", "_");
            lines.append("    " + cid + "[Class: " + c.name + "]");
        }

        for f in fns {
            fid = ("fn_" + f.name).replace(" ", "_");
            lines.append("    " + fid + "[fn " + f.name + "()]");
        }

        for c in classes {
            cid = ("class_" + c.name).replace(" ", "_");
            bases = [c <-:Inherits:<- (`?Class)];
            for b in bases {
                bid = ("class_" + b.name).replace(" ", "_");
                lines.append("    " + bid + " --> " + cid);
            }
        }

        for f in fns {
            fid = ("fn_" + f.name).replace(" ", "_");
            outs = [f ->:Calls:-> (`?Function)];
            for t in outs {
                tid = ("fn_" + t.name).replace(" ", "_");
                lines.append("    " + fid + " --> " + tid);
            }
        }

        return "\n".join(lines);
    }

    def compose_markdown(tree_txt_path: str) -> str by llm(method="ReAct");

can generate with entry {
    print("Generating markdown documentation...");
    
    # --- Read actual directory tree content ---
    let tree_txt = os.path.join(self.temp_dir, "file_tree.txt");
    let tree_content = "";
    if os.path.exists(tree_txt) {
        tree_content = open(tree_txt, "r", encoding="utf-8").read();
    } else {
        tree_content = "No file tree found.";
    }

    # --- Build mermaid diagram safely ---
    let mm = self.mermaid_from_ccg();
    
    # --- Assemble base markdown header ---
    let base = "# Codebase Documentation — " + self.repo_name + "\n\n";
    if self.readme_summary {
        base += "## Overview\n" + self.readme_summary + "\n\n";
    }

    #base += "## Architecture Diagram\n```mermaid\n" + mm + "\n```\n\n";

    let files_summary = "Files in repository:\n" + "\n".join(self.file_index);
    let md = self.compose_markdown(tree_content + "\n\n" + files_summary + "\n\n" + self.ccg_nodes);

    if type(md) != str {
        md = "" if not md else str(md);
    }
    
    md = md.replace("undefined", "").strip();
    let timestamp = get_timestamp();

    let final_md = base + md + "\n\n---\nGenerated automatically by Codebase Genius on " + timestamp + "";

    # --- Save output file ---
    let output_folder = os.path.join(self.temp_dir, "outputs", self.repo_name);
    if not os.path.exists(output_folder) {
        os.makedirs(output_folder);
    }

    self.output_md = os.path.join(output_folder, "docs.md");
    with open(self.output_md, "w", encoding="utf-8") as f {
        f.write(final_md);
    }

    print("Markdown saved at " + self.output_md);
    return self.output_md;
}
}
sem DocGenie.compose_markdown = """
You are a technical documentation generator for an AI + Jaclang + Python codebase.

Inputs:
- README summary describing purpose and goals.
- A full directory tree (including nested folders and files).
- A list of detected classes, functions, and relationships (CCG nodes).

Rules:
1. Base every section on real files from the provided structure.
2. For each file, briefly describe what it does (infer from name and context).
3. If functions or classes are provided, list them under their respective files with bullet points and short explanations.
4. If Jac files are detected, describe walkers, nodes, or edges inside them.

Generate Markdown with these sections:
1. **Project Overview**
2. **Installation & Setup**
3. **Usage Guide**
4. **Detailed File & Folder Structure**
   - Include subfolders, each file, and a short purpose.
5. **Component & Function Summary**
   - Table with: *File*, *Type (Python/Jac)*, *Description*.
6.  *Elements of the code in .py, .jac, etc by naming and describing names of Classes, Functions, Nodes, Edges, Walkers)*,

7. **Architecture & Relationships**
   - Use the Mermaid diagram and CCG to explain how parts interact.
8. **API / Class Reference**
   - List major functions and methods, include small code examples if found.
9. **Limitations & Known Issues**
10. **Future Enhancements**
11. **Credits & Licensing**
12. **Footer**

Formatting:
- Use Markdown headings and code blocks.
- Do not invent nonexistent files or APIs.
- Use concise, technical prose.
- Return Markdown only.
""";

